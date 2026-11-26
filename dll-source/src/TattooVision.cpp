// S329 (tattoo-overhaul 9, step D, ruling D-T10): what a tattoo texture shows, measured natively.
// Reads one SlaveTats texture (DDS: DXT1 / DXT3 / DXT5 and uncompressed 16/24/32-bit; BC7 and others are not decoded
// and fall back to the name), picks a small mip level, and measures the inked pixels (alpha > 40): where they sit,
// how big they are, their shape, and their main colours. For Body textures the placement comes from a body-UV region
// table measured in S329 from 262 installed tattoos whose names state where they go (the back half of the body is the
// top of the texture, the front the bottom; arms and legs on the outer edges; the wearer's left is the texture's right).
// The result is a short plain-English fact line the description prompt (ded_tattoo_describe) turns into a sentence.
#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

namespace
{
    struct Stats
    {
        std::uint64_t ink = 0, total = 0;
        double        sx = 0, sy = 0;
        int           minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
        std::uint64_t left = 0, right = 0, mid = 0;   // ink left of, right of, and on the centre column
        std::array<std::uint64_t, 11> col{};          // colour buckets, see kColorNames
        int           w = 0, h = 0;
    };

    constexpr const char* kColorNames[11] = { "black", "grey", "white", "red", "orange", "yellow", "green", "teal", "blue", "purple", "pink" };

    int ColorBucket(int r, int g, int b)
    {
        const int mx = (std::max)({ r, g, b }), mn = (std::min)({ r, g, b });
        const double v = mx / 255.0, s = mx ? (mx - mn) / static_cast<double>(mx) : 0.0;
        if (v < 0.22) return 0;
        if (s < 0.18) return v > 0.8 ? 2 : 1;
        double hdeg;
        const double d = static_cast<double>(mx - mn);
        if (mx == r) hdeg = 60.0 * std::fmod((g - b) / d, 6.0);
        else if (mx == g) hdeg = 60.0 * ((b - r) / d + 2.0);
        else hdeg = 60.0 * ((r - g) / d + 4.0);
        if (hdeg < 0) hdeg += 360.0;
        if (hdeg < 15 || hdeg >= 345) return 3;
        if (hdeg < 40) return 4;
        if (hdeg < 70) return 5;
        if (hdeg < 160) return 6;
        if (hdeg < 195) return 7;
        if (hdeg < 255) return 8;
        if (hdeg < 290) return 9;
        return 10;
    }

    void Pixel(Stats& s, int x, int y, int r, int g, int b, int a)
    {
        ++s.total;
        if (a <= 40) return;
        ++s.ink;
        s.sx += x; s.sy += y;
        s.minX = (std::min)(s.minX, x); s.maxX = (std::max)(s.maxX, x);
        s.minY = (std::min)(s.minY, y); s.maxY = (std::max)(s.maxY, y);
        const int c = s.w / 2, band = (std::max)(1, s.w / 100);
        if (x < c - band) ++s.left; else if (x > c + band) ++s.right; else ++s.mid;
        ++s.col[ColorBucket(r, g, b)];
    }

    void Rgb565(std::uint16_t c, int& r, int& g, int& b)
    {
        r = ((c >> 11) & 31) * 255 / 31;
        g = ((c >> 5) & 63) * 255 / 63;
        b = (c & 31) * 255 / 31;
    }

    // One BCn colour block (8 bytes) into 16 RGBA texels; a_dxt1 enables DXT1's 3-colour + transparent mode.
    void ColorBlock(const std::uint8_t* p, bool a_dxt1, std::array<std::array<int, 4>, 16>& out)
    {
        const std::uint16_t c0 = static_cast<std::uint16_t>(p[0] | (p[1] << 8)), c1 = static_cast<std::uint16_t>(p[2] | (p[3] << 8));
        int pal[4][4];
        Rgb565(c0, pal[0][0], pal[0][1], pal[0][2]);
        Rgb565(c1, pal[1][0], pal[1][1], pal[1][2]);
        pal[0][3] = pal[1][3] = 255;
        if (!a_dxt1 || c0 > c1) {
            for (int k = 0; k < 3; ++k) {
                pal[2][k] = (2 * pal[0][k] + pal[1][k]) / 3;
                pal[3][k] = (pal[0][k] + 2 * pal[1][k]) / 3;
            }
            pal[2][3] = pal[3][3] = 255;
        } else {
            for (int k = 0; k < 3; ++k) { pal[2][k] = (pal[0][k] + pal[1][k]) / 2; pal[3][k] = 0; }
            pal[2][3] = 255; pal[3][3] = 0;
        }
        const std::uint32_t bits = p[4] | (p[5] << 8) | (p[6] << 16) | (static_cast<std::uint32_t>(p[7]) << 24);
        for (int i = 0; i < 16; ++i) {
            const int idx = (bits >> (2 * i)) & 3;
            out[i] = { pal[idx][0], pal[idx][1], pal[idx][2], pal[idx][3] };
        }
    }

    void Dxt5Alpha(const std::uint8_t* p, std::array<std::array<int, 4>, 16>& out)
    {
        int a[8];
        a[0] = p[0]; a[1] = p[1];
        if (a[0] > a[1]) for (int i = 1; i < 7; ++i) a[i + 1] = ((7 - i) * a[0] + i * a[1]) / 7;
        else {
            for (int i = 1; i < 5; ++i) a[i + 1] = ((5 - i) * a[0] + i * a[1]) / 5;
            a[6] = 0; a[7] = 255;
        }
        std::uint64_t bits = 0;
        for (int i = 0; i < 6; ++i) bits |= static_cast<std::uint64_t>(p[2 + i]) << (8 * i);
        for (int i = 0; i < 16; ++i) out[i][3] = a[(bits >> (3 * i)) & 7];
    }

    enum class Fmt { None, Dxt1, Dxt3, Dxt5, Rgb };

    struct Dds
    {
        Fmt           fmt = Fmt::None;
        int           w = 0, h = 0, mips = 1, bpp = 0;
        std::uint32_t mr = 0, mg = 0, mb = 0, ma = 0;
        std::size_t   dataOff = 128;
        std::string   why;
    };

    std::uint32_t U32(const std::uint8_t* p) { return p[0] | (p[1] << 8) | (p[2] << 16) | (static_cast<std::uint32_t>(p[3]) << 24); }

    bool ReadHeader(std::ifstream& in, Dds& d)
    {
        std::uint8_t h[148]{};
        in.read(reinterpret_cast<char*>(h), 148);
        if (in.gcount() < 128 || std::memcmp(h, "DDS ", 4) != 0) { d.why = "not a DDS file"; return false; }
        d.h = static_cast<int>(U32(h + 12));
        d.w = static_cast<int>(U32(h + 16));
        d.mips = (std::max)(1, static_cast<int>(U32(h + 28)));
        const std::uint32_t pfFlags = U32(h + 80);
        const char* cc = reinterpret_cast<const char*>(h + 84);
        if (pfFlags & 0x4) {
            if (!std::memcmp(cc, "DXT1", 4)) d.fmt = Fmt::Dxt1;
            else if (!std::memcmp(cc, "DXT2", 4) || !std::memcmp(cc, "DXT3", 4)) d.fmt = Fmt::Dxt3;
            else if (!std::memcmp(cc, "DXT4", 4) || !std::memcmp(cc, "DXT5", 4)) d.fmt = Fmt::Dxt5;
            else if (!std::memcmp(cc, "DX10", 4)) {
                const std::uint32_t dxgi = U32(h + 128);
                d.dataOff = 148;
                if (dxgi >= 70 && dxgi <= 72) d.fmt = Fmt::Dxt1;
                else if (dxgi >= 73 && dxgi <= 75) d.fmt = Fmt::Dxt3;
                else if (dxgi >= 76 && dxgi <= 78) d.fmt = Fmt::Dxt5;
                else if (dxgi == 87 || dxgi == 91) { d.fmt = Fmt::Rgb; d.bpp = 32; d.mr = 0xFF0000; d.mg = 0xFF00; d.mb = 0xFF; d.ma = 0xFF000000; }
                else if (dxgi == 28 || dxgi == 29) { d.fmt = Fmt::Rgb; d.bpp = 32; d.mr = 0xFF; d.mg = 0xFF00; d.mb = 0xFF0000; d.ma = 0xFF000000; }
                else { d.why = "DXGI format " + std::to_string(dxgi) + " is not decoded"; return false; }
            } else { d.why = std::string("FourCC ") + std::string(cc, 4) + " is not decoded"; return false; }
        } else if (pfFlags & 0x20000) {   // luminance (+ alpha): one grey channel
            d.fmt = Fmt::Rgb;
            d.bpp = static_cast<int>(U32(h + 88));
            d.mr = d.mg = d.mb = U32(h + 92);
            d.ma = (pfFlags & 0x1) ? U32(h + 104) : 0;
            if (d.bpp != 8 && d.bpp != 16) { d.why = std::to_string(d.bpp) + "-bit luminance is not decoded"; return false; }
        } else if (pfFlags & 0x2) {       // alpha only
            d.fmt = Fmt::Rgb;
            d.bpp = static_cast<int>(U32(h + 88));
            d.mr = d.mg = d.mb = 0;
            d.ma = U32(h + 104);
            if (d.bpp != 8) { d.why = std::to_string(d.bpp) + "-bit alpha is not decoded"; return false; }
        } else if (pfFlags & 0x40) {
            d.fmt = Fmt::Rgb;
            d.bpp = static_cast<int>(U32(h + 88));
            d.mr = U32(h + 92); d.mg = U32(h + 96); d.mb = U32(h + 100);
            d.ma = (pfFlags & 0x1) ? U32(h + 104) : 0;
            if (d.bpp != 16 && d.bpp != 24 && d.bpp != 32) { d.why = std::to_string(d.bpp) + "-bit pixels are not decoded"; return false; }
        } else { d.why = "unknown pixel format"; return false; }
        if (d.w <= 0 || d.h <= 0 || d.w > 16384 || d.h > 16384) { d.why = "bad size"; return false; }
        return true;
    }

    std::size_t LevelBytes(const Dds& d, int w, int h)
    {
        if (d.fmt == Fmt::Rgb) return static_cast<std::size_t>(w) * h * (d.bpp / 8);
        const std::size_t blocks = static_cast<std::size_t>((std::max)(1, (w + 3) / 4)) * (std::max)(1, (h + 3) / 4);
        return blocks * (d.fmt == Fmt::Dxt1 ? 8 : 16);
    }

    int MaskVal(std::uint32_t px, std::uint32_t mask)
    {
        if (!mask) return 0;
        unsigned long shift = 0;
        while (!((mask >> shift) & 1)) ++shift;
        const std::uint32_t m = mask >> shift;
        return static_cast<int>(((px >> shift) & m) * 255 / m);
    }

    bool Decode(const std::string& a_path, Stats& s, std::string& a_why)
    {
        std::ifstream in(a_path, std::ios::binary);
        if (!in) { a_why = "texture not found as a loose file"; return false; }
        Dds d;
        if (!ReadHeader(in, d)) { a_why = d.why; return false; }
        // the first mip level no wider than 256 texels, when the file carries mips
        std::size_t off = d.dataOff;
        int w = d.w, h = d.h;
        for (int lv = 0; lv < d.mips - 1 && (std::max)(w, h) > 256; ++lv) {
            off += LevelBytes(d, w, h);
            w = (std::max)(1, w / 2); h = (std::max)(1, h / 2);
        }
        const std::size_t bytes = LevelBytes(d, w, h);
        std::vector<std::uint8_t> buf(bytes);
        in.seekg(static_cast<std::streamoff>(off));
        in.read(reinterpret_cast<char*>(buf.data()), static_cast<std::streamsize>(bytes));
        if (static_cast<std::size_t>(in.gcount()) != bytes) { a_why = "texture data is short"; return false; }
        s.w = w; s.h = h;
        if (d.fmt == Fmt::Rgb) {
            const int bp = d.bpp / 8;
            for (int y = 0; y < h; ++y)
                for (int x = 0; x < w; ++x) {
                    const std::uint8_t* p = buf.data() + (static_cast<std::size_t>(y) * w + x) * bp;
                    std::uint32_t px = 0;
                    for (int k = 0; k < bp; ++k) px |= static_cast<std::uint32_t>(p[k]) << (8 * k);
                    Pixel(s, x, y, MaskVal(px, d.mr), MaskVal(px, d.mg), MaskVal(px, d.mb), d.ma ? MaskVal(px, d.ma) : 255);   // alpha-only: black ink
                }
            return true;
        }
        const int bw = (std::max)(1, (w + 3) / 4), bh = (std::max)(1, (h + 3) / 4);
        const std::size_t blk = d.fmt == Fmt::Dxt1 ? 8 : 16;
        std::array<std::array<int, 4>, 16> tex{};
        for (int by = 0; by < bh; ++by)
            for (int bx = 0; bx < bw; ++bx) {
                const std::uint8_t* p = buf.data() + (static_cast<std::size_t>(by) * bw + bx) * blk;
                if (d.fmt == Fmt::Dxt1) ColorBlock(p, true, tex);
                else {
                    ColorBlock(p + 8, false, tex);
                    if (d.fmt == Fmt::Dxt5) Dxt5Alpha(p, tex);
                    else for (int i = 0; i < 16; ++i) tex[i][3] = ((p[i / 2] >> (4 * (i & 1))) & 15) * 17;
                }
                for (int i = 0; i < 16; ++i) {
                    const int x = bx * 4 + (i & 3), y = by * 4 + (i >> 2);
                    if (x < w && y < h) Pixel(s, x, y, tex[i][0], tex[i][1], tex[i][2], tex[i][3]);
                }
            }
        return true;
    }

    // Body UV (u across, v down) -> a body region; S329 measurements (workstream tattoo-overhaul 9, step D).
    std::string BodyRegion(double u, double v, bool a_pair)
    {
        const double dx = std::fabs(u - 0.5);
        const std::string side = u < 0.5 ? "right" : "left";
        if (dx < 0.15) {
            if (v < 0.16) return a_pair ? "both buttocks" : "buttocks";
            if (v < 0.35) return "lower back or buttocks";
            if (v < 0.50) return "back";
            if (v < 0.58) return "upper back or shoulders";
            if (v < 0.72) return "chest";
            if (v < 0.86) return "belly";
            return "lower belly or pubic area";
        }
        if (dx > 0.37) {
            if (v >= 0.35 && v < 0.65) return side + " arm";
            if (v >= 0.80) return side + " lower leg";
            if (v >= 0.65) return side + " thigh";
            return side + " side";
        }
        if (v >= 0.65) return side + " thigh";
        if (v >= 0.35) return side + " upper arm";
        return side + " side of the body";
    }
}

// The fact line for one tattoo (empty a_why = success). a_texture is the pack json's "texture" value.
std::string TattooVisualFacts(const std::string& a_texture, const std::string& a_area, std::string& a_why)
{
    a_why.clear();
    std::string rel = a_texture;
    for (auto& c : rel) if (c == '/') c = '\\';
    Stats s;
    if (!Decode("Data\\Textures\\Actors\\Character\\slavetats\\" + rel, s, a_why)) return {};
    if (s.ink < 4 || !s.total) { a_why = "no inked pixels"; return {}; }
    const double cover = static_cast<double>(s.ink) / s.total;
    if (cover > 0.85) { a_why = "no transparency to measure"; return {}; }
    const double u = s.sx / s.ink / s.w, v = s.sy / s.ink / s.h;
    const double bw = static_cast<double>(s.maxX - s.minX + 1) / s.w, bh = static_cast<double>(s.maxY - s.minY + 1) / s.h;
    // a mirrored pair: ink on both sides of the centre column, little on it
    const bool pair = s.left > s.ink / 4 && s.right > s.ink / 4 && s.mid * 50 < s.ink;
    std::string area = a_area;
    for (auto& c : area) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    const bool body = area == "body";
    std::string out = "placement: ";
    out += body ? BodyRegion(u, v, pair) : area.empty() ? std::string("body") : area;
    if (pair && body && std::fabs(u - 0.5) < 0.15) out += " (a matching pair, one on each side)";
    if (body) {   // size and shape only mean something against the whole-body texture
        const double span = (std::max)(bw, bh);
        out += "; size: ";
        out += span < 0.05 ? "small" : span < 0.12 ? "medium" : span < 0.25 ? "large" : "sprawling";
        const double aspect = bh > 0 ? bw / bh : 1.0;
        out += "; shape: ";
        out += aspect > 2.5 ? "a wide horizontal band (often a line of lettering)" : aspect < 0.4 ? "a tall narrow strip" : "compact";
    }
    // main colours: the buckets with at least 20% of the ink
    std::vector<std::pair<std::uint64_t, int>> cols;
    for (int i = 0; i < 11; ++i) if (s.col[i] * 5 >= s.ink) cols.push_back({ s.col[i], i });
    std::sort(cols.begin(), cols.end(), [](const auto& a, const auto& b) { return a.first > b.first; });
    out += "; drawn in ";
    if (cols.empty()) out += "mixed colours";
    for (std::size_t i = 0; i < cols.size() && i < 2; ++i) {
        if (i) out += " and ";
        out += kColorNames[cols[i].second];
    }
    if (!cols.empty() && (cols[0].second == 2 || cols[0].second == 1)) out += " (likely tinted with the colour chosen when applied)";
    return out;
}
