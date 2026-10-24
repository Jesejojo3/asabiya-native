// Package mapsource is a local I/O adapter. The simulation receives numeric
// rasters only and does not read HTML, images, paths, or renderer resources.
package mapsource

import (
	"bytes"
	"compress/zlib"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"math"
	"os"
	"path/filepath"
	"regexp"

	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

const legacyHTMLSHA256 = "988ce360e70d2d034a3898f60b9a4c38d40b0ab56dd7a147329740f15fa8e9e9"
const maxSourceBytes = 64 << 20
const Resampling = "native/bilinear-rgb8-v1"

func ReadConfig(path string) (sim.WorldSource, error) {
	s := sim.DefaultWorldSource()
	data, err := os.ReadFile(path)
	if err != nil {
		return s, err
	}
	d := json.NewDecoder(bytes.NewReader(data))
	d.DisallowUnknownFields()
	if err = d.Decode(&s); err != nil {
		return s, err
	}
	var extra any
	if d.Decode(&extra) != io.EOF {
		return s, fmt.Errorf("source file must contain one JSON value")
	}
	base, err := filepath.Abs(filepath.Dir(path))
	if err != nil {
		return s, err
	}
	for k := range s.Assets {
		if !filepath.IsAbs(s.Assets[k].Path) {
			s.Assets[k].Path = filepath.Join(base, s.Assets[k].Path)
		}
	}
	return s, nil
}

// Load verifies recorded asset hashes on replay. Source paths may be relocated,
// but changing asset bytes requires a new world rather than silently replaying.
func Load(c sim.WorldConfig, s sim.WorldSource) (sim.WorldSource, sim.WorldInputs, error) {
	var in sim.WorldInputs
	if c.Width < 24 || c.Width > 400 || c.Height < 16 || c.Height > 200 || c.Detail < 1 || c.Detail > 4 {
		return s, in, fmt.Errorf("invalid world dimensions")
	}
	if s.Kind == "earth" && (c.Width != 400 || c.Height != 200 || c.Detail != 4) {
		return s, in, fmt.Errorf("legacy Earth requires logical 400x200, detail 4")
	}
	if s.Resampling != "" && s.Resampling != Resampling {
		return s, in, fmt.Errorf("unsupported resampling %q", s.Resampling)
	}
	width, height := c.Width*c.Detail, c.Height*c.Detail
	seen := make(map[string]bool)
	s.Assets = append([]sim.SourceAsset(nil), s.Assets...)
	for k := range s.Assets {
		asset := &s.Assets[k]
		if seen[asset.Role] {
			return s, in, fmt.Errorf("duplicate source role %s", asset.Role)
		}
		seen[asset.Role] = true
		switch asset.Role {
		case "earth-html", "height", "temperature", "precipitation", "koppen":
		default:
			return s, in, fmt.Errorf("unknown source role %s", asset.Role)
		}
		if s.Kind == "earth" && asset.Role == "height" || (s.Kind != "earth" && s.Kind != "imported") && asset.Role == "earth-html" {
			return s, in, fmt.Errorf("asset %s conflicts with source kind %s", asset.Role, s.Kind)
		}
		if asset.Role == "earth-html" && (c.Width != 400 || c.Height != 200 || c.Detail != 4) {
			return s, in, fmt.Errorf("Earth asset requires logical 400x200, detail 4")
		}
		path, err := filepath.Abs(asset.Path)
		if err != nil {
			return s, in, err
		}
		asset.Path = path
		file, err := os.Open(path)
		if err != nil {
			return s, in, err
		}
		raw, readErr := io.ReadAll(io.LimitReader(file, maxSourceBytes+1))
		closeErr := file.Close()
		if readErr != nil {
			return s, in, readErr
		}
		if closeErr != nil {
			return s, in, closeErr
		}
		if len(raw) > maxSourceBytes {
			return s, in, fmt.Errorf("source exceeds 64 MiB")
		}
		hash := sha256.Sum256(raw)
		sha := hex.EncodeToString(hash[:])
		if asset.SHA256 != "" && asset.SHA256 != sha {
			return s, in, fmt.Errorf("asset %s SHA-256 differs", asset.Role)
		}
		if asset.Bytes != 0 && asset.Bytes != int64(len(raw)) {
			return s, in, fmt.Errorf("asset %s size differs", asset.Role)
		}
		asset.SHA256, asset.Bytes = sha, int64(len(raw))
		switch asset.Role {
		case "earth-html":
			if sha != legacyHTMLSHA256 {
				return s, in, fmt.Errorf("Earth requires the preserved v0.6 HTML, SHA-256 differs")
			}
			var err error
			in.Height, in.Koppen, err = decodeEarth(raw, width, height)
			if err != nil {
				return s, in, err
			}
		case "koppen":
			if s.Kind == "earth" {
				return s, in, fmt.Errorf("Earth Koppen data comes from its HTML; overriding it requires an imported world")
			}
			if len(raw) != width*height {
				return s, in, fmt.Errorf("Koppen file must contain exactly %d u8 codes", width*height)
			}
			in.Koppen = append([]uint8(nil), raw...)
		default:
			if math.IsNaN(asset.Min) || math.IsNaN(asset.Max) || math.IsInf(asset.Min, 0) || math.IsInf(asset.Max, 0) || asset.Min >= asset.Max {
				return s, in, fmt.Errorf("%s min must be finite and less than max", asset.Role)
			}
			if asset.Role == "height" && asset.Midpoint && !(asset.Min < 0 && asset.Max > 0) {
				return s, in, fmt.Errorf("midpoint height import requires min < 0 < max")
			}
			if asset.Role == "precipitation" && asset.Min < 0 {
				return s, in, fmt.Errorf("precipitation minimum must be nonnegative")
			}
			values, err := decodeRaster(raw, width, height, *asset)
			if err != nil {
				return s, in, fmt.Errorf("%s: %w", asset.Role, err)
			}
			s.Resampling = Resampling
			switch asset.Role {
			case "height":
				in.Height = values
			case "temperature":
				in.Temperature = values
			case "precipitation":
				in.Precipitation = values
			}
		}
	}
	if s.Kind == "earth" && !seen["earth-html"] {
		return s, in, fmt.Errorf("Earth requires an earth-html asset")
	}
	if seen["earth-html"] && (seen["height"] || seen["koppen"]) {
		return s, in, fmt.Errorf("earth-html already supplies elevation and Koppen; conflicting assets are not allowed")
	}
	// Importing the preserved rasters does not opt into the legacy Earth's
	// fixed founders and hearths. History keeps the existing imported-world rules.
	if s.Kind == "imported" && !seen["height"] && !seen["earth-html"] {
		return s, in, fmt.Errorf("imported world requires a height image")
	}
	return s, in, nil
}

func Generate(c sim.WorldConfig, s sim.WorldSource, retain bool) (*sim.World, *sim.Surface, error) {
	s, in, err := Load(c, s)
	if err != nil {
		return nil, nil, err
	}
	return sim.GenerateWorldWithInputs(c, s, in, retain)
}

func inflateAsset(html []byte, name string, length int) ([]byte, error) {
	pattern := regexp.MustCompile(`\bconst\s+` + regexp.QuoteMeta(name) + `\s*=\s*"([A-Za-z0-9+/=]+)"`)
	match := pattern.FindSubmatch(html)
	if len(match) != 2 {
		return nil, fmt.Errorf("missing Earth asset %s", name)
	}
	compressed, err := base64.StdEncoding.DecodeString(string(match[1]))
	if err != nil {
		return nil, err
	}
	z, err := zlib.NewReader(bytes.NewReader(compressed))
	if err != nil {
		return nil, err
	}
	data, err := io.ReadAll(io.LimitReader(z, int64(length)+1))
	closeErr := z.Close()
	if err != nil {
		return nil, err
	}
	if closeErr != nil {
		return nil, closeErr
	}
	if len(data) != length {
		return nil, fmt.Errorf("%s decoded length %d, expected %d", name, len(data), length)
	}
	return data, nil
}
func decodeEarth(html []byte, width, height int) ([]float32, []uint8, error) {
	d, err := inflateAsset(html, "EARTH_ELEV_B64", width*height*2)
	if err != nil {
		return nil, nil, err
	}
	kg, err := inflateAsset(html, "KOPPEN_B64", width*height)
	if err != nil {
		return nil, nil, err
	}
	e := make([]float32, width*height)
	for y := 0; y < height; y++ {
		acc := 0.
		for x := 0; x < width; x++ {
			i := y*width + x
			acc += float64(int16(binary.LittleEndian.Uint16(d[i*2 : i*2+2])))
			e[i] = float32(acc)
		}
	}
	return e, kg, nil
}

// Browser canvas smoothing is not specified across browsers. This native
// adapter instead fixes pixel-center bilinear interpolation and RGB8 rounding.
// Luminance and scaled outputs retain the original Float32Array write points.
func decodeRaster(raw []byte, width, height int, asset sim.SourceAsset) ([]float32, error) {
	cfg, _, err := image.DecodeConfig(bytes.NewReader(raw))
	if err != nil {
		return nil, err
	}
	if cfg.Width < 1 || cfg.Height < 1 || cfg.Width > 16384 || cfg.Height > 16384 || int64(cfg.Width)*int64(cfg.Height) > 32_000_000 {
		return nil, fmt.Errorf("image dimensions exceed import limits")
	}
	img, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return nil, err
	}
	bounds := img.Bounds()
	pixel := func(x, y int) color.NRGBA {
		x = max(0, min(cfg.Width-1, x))
		y = max(0, min(cfg.Height-1, y))
		p := color.NRGBAModel.Convert(img.At(bounds.Min.X+x, bounds.Min.Y+y)).(color.NRGBA)
		if p.A == 0 {
			p.R, p.G, p.B = 0, 0, 0
		}
		return p
	}
	out := make([]float32, width*height)
	for y := 0; y < height; y++ {
		sy := (float64(y)+.5)*float64(cfg.Height)/float64(height) - .5
		y0 := int(math.Floor(sy))
		fy := sy - float64(y0)
		for x := 0; x < width; x++ {
			sx := (float64(x)+.5)*float64(cfg.Width)/float64(width) - .5
			x0 := int(math.Floor(sx))
			fx := sx - float64(x0)
			p00, p10, p01, p11 := pixel(x0, y0), pixel(x0+1, y0), pixel(x0, y0+1), pixel(x0+1, y0+1)
			channel := func(a, b, c, d uint8) float64 {
				v := (float64(a)*(1-fx)+float64(b)*fx)*(1-fy) + (float64(c)*(1-fx)+float64(d)*fx)*fy
				return math.Floor(v + .5)
			}
			r, g, b := channel(p00.R, p10.R, p01.R, p11.R), channel(p00.G, p10.G, p01.G, p11.G), channel(p00.B, p10.B, p01.B, p11.B)
			v := float64(float32((r*.299 + g*.587 + b*.114) / 255))
			scaled := asset.Min + v*(asset.Max-asset.Min)
			if asset.Role == "height" && asset.Midpoint {
				if v >= .5 {
					scaled = (v - .5) * 2 * asset.Max
				} else {
					scaled = (.5 - v) * 2 * asset.Min
				}
			}
			out[y*width+x] = float32(scaled)
		}
	}
	return out, nil
}
