/**
Text formatting and drawing.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.text;

import std.array : Appender;
import std.uni : isAlphaNum, toLower, toUpper;
import beamui.core.editable : TabSize;
import beamui.core.functions : clamp, max, move;
import beamui.core.geometry : Point, Size;
import beamui.core.logger;
import beamui.graphics.colors : Color;
import beamui.graphics.drawbuf;
import beamui.graphics.fonts;

/// Specifies text alignment
enum TextAlign : ubyte
{
    start,
    center,
    end,
    justify
}

/// Decoration added to text (like underline)
struct TextDecoration
{
    enum Line : ubyte
    {
        none,
        overline,
        underline,
        lineThrough
    }
    enum Style : ubyte
    {
        solid,
        doubled,
        dotted,
        dashed,
        wavy
    }
    alias none = Line.none;
    alias overline = Line.overline;
    alias underline = Line.underline;
    alias lineThrough = Line.lineThrough;
    alias solid = Style.solid;

    Color color;
    Line line;
    Style style;
}

/// Controls how text with `&` hotkey marks should be displayed
enum TextHotkey : ubyte
{
    /// Treat as usual text
    ignore,
    /// Only hide `&` marks
    hidden,
    /// Underline hotkey letter that goes after `&`
    underline,
    /// Underline hotkey letter that goes after `&` only when Alt pressed
    underlineOnAlt
}

/// Specifies how text that doesn't fit and is not displayed should behave
enum TextOverflow : ubyte
{
    clip,
    ellipsis,
    ellipsisMiddle
}

/// Controls capitalization of text
enum TextTransform : ubyte
{
    none,
    capitalize,
    uppercase,
    lowercase
}

/// Holds text properties - font style, colors, and so on
struct TextStyle
{
    /// Font that also contains size, style, weight properties
    Font font;
    /// Size of the tab character in number of spaces
    TabSize tabSize;
    TextAlign alignment;
    TextDecoration decoration;
    TextHotkey hotkey;
    TextOverflow overflow;
    TextTransform transform;
    /// Text color
    Color color;
    /// Text background color
    Color backgroundColor;
}

/// Text style applied to a part of text line
struct MarkupUnit
{
    /// Style pointer
    TextStyle* style;
    /// Starting char index
    int start;
}

/// Text string line
struct TextLine
{
    @property
    {
        /// Text data
        dstring str() const { return _str; }
        /// ditto
        void str(dstring s)
        {
            _str = s;
            _needToMeasure = true;
        }

        /// Number of characters in the line
        size_t length() const
        {
            return _str.length;
        }

        /// Glyphs array, available after measuring
        const(GlyphRef[]) glyphs() const
        {
            return !_needToMeasure ? _glyphs[0 .. _str.length] : null;
        }
        /// Measured character widths
        const(ushort[]) charWidths() const
        {
            return !_needToMeasure ? _charWidths[0 .. _str.length] : null;
        }
        /// Measured text line size
        Size size() const { return _size; }

        /// Returns true whether text is modified and needs to be measured again
        bool needToMeasure() const { return _needToMeasure; }
    }

    private
    {
        dstring _str;
        GlyphRef[] _glyphs;
        ushort[] _charWidths;
        Size _size;

        bool _needToMeasure = true;
    }

    this(dstring text)
    {
        _str = text;
    }

    /**
    Measure text string to calculate char sizes and total text size.

    Supports Tab character processing and processing of menu item labels like `&File`.
    */
    void measure(const ref TextStyle style)
    {
        Font font = (cast(TextStyle)style).font;
        assert(font !is null, "Font is mandatory");

        const size_t len = _str.length;
        if (len == 0)
        {
            // trivial case; do not resize buffers
            _size = Size(0, font.height);
            _needToMeasure = false;
            return;
        }

        const bool fixed = font.isFixed;
        const ushort fixedCharWidth = cast(ushort)font.charWidth('M');
        const int spaceWidth = fixed ? fixedCharWidth : font.spaceWidth;
        const bool useKerning = !fixed && font.allowKerning;
        const bool hotkeys = style.hotkey != TextHotkey.ignore;

        if (_charWidths.length < len || _charWidths.length >= len * 5)
            _charWidths.length = len;
        if (_glyphs.length < len || _glyphs.length >= len * 5)
            _glyphs.length = len;
        auto pwidths = _charWidths.ptr;
        auto pglyphs = _glyphs.ptr;
        int x;
        dchar prevChar = 0;
        foreach (i, ch; _str)
        {
            if (ch == '\t')
            {
                // calculate tab stop
                int n = x / (spaceWidth * style.tabSize) + 1;
                int tabPosition = spaceWidth * style.tabSize * n;
                pwidths[i] = cast(ushort)(tabPosition - x);
                pglyphs[i] = null;
                x = tabPosition;
                prevChar = 0;
                continue;
            }
            else if (hotkeys && ch == '&')
            {
                pwidths[i] = 0;
                pglyphs[i] = null;
                prevChar = 0;
                continue; // skip '&' in hotkey when measuring
            }
            // apply text transformation
            dchar trch = ch;
            if (style.transform == TextTransform.lowercase)
            {
                trch = toLower(ch);
            }
            else if (style.transform == TextTransform.uppercase)
            {
                trch = toUpper(ch);
            }
            else if (style.transform == TextTransform.capitalize)
            {
                if (!isAlphaNum(prevChar))
                    trch = toUpper(ch);
            }
            // retrieve glyph
            GlyphRef glyph = font.getCharGlyph(trch);
            pglyphs[i] = glyph;
            if (fixed)
            {
                // fast calculation for fixed pitch
                pwidths[i] = fixedCharWidth;
                x += fixedCharWidth;
            }
            else
            {
                if (glyph is null)
                {
                    // if no glyph, treat as zero width
                    pwidths[i] = 0;
                    prevChar = 0;
                    continue;
                }
                int kerningDelta = useKerning && prevChar ? font.getKerningOffset(prevChar, ch) : 0;
                if (kerningDelta != 0)
                {
                    // shrink previous glyph (or expand, maybe)
                    pwidths[i - 1] += cast(short)(kerningDelta / 64);
                }
                int w = max(glyph.widthScaled >> 6, glyph.originX + glyph.correctedBlackBoxX);
                pwidths[i] = cast(ushort)w;
                x += w;
            }
            prevChar = trch;
        }
        _size = Size(x, font.height);
        _needToMeasure = false;
    }

    /// Split line by width
    TextLine[] wrap(int width)
    {
        if (width <= 0)
            return null;

        import std.ascii : isWhite;

        TextLine[] result;
        const size_t len = _str.length;
        const pstr = _str.ptr;
        const pwidths = _charWidths.ptr;
        size_t lineStart;
        size_t lastWordEnd;
        int lastWordEndX;
        int lineWidth;
        bool whitespace;
        for (size_t i; i < len; i++)
        {
            const dchar ch = pstr[i];
            // split by whitespace characters
            if (isWhite(ch))
            {
                // track last word end
                if (!whitespace)
                {
                    lastWordEnd = i;
                    lastWordEndX = lineWidth;
                }
                whitespace = true;
                // skip this char
                lineWidth += pwidths[i];
                continue;
            }
            whitespace = false;
            lineWidth += pwidths[i];
            if (i > lineStart && lineWidth > width)
            {
                // need splitting
                size_t lineEnd = i;
                if (lastWordEnd > lineStart && lastWordEndX >= width / 3)
                {
                    // split on word bound
                    lineEnd = lastWordEnd;
                    lineWidth = lastWordEndX;
                }
                // add line
                TextLine line;
                line._str = _str[lineStart .. lineEnd];
                line._glyphs = _glyphs[lineStart .. lineEnd];
                line._charWidths = _charWidths[lineStart .. lineEnd];
                line._size = Size(lineWidth, _size.h);
                result ~= line;

                // find next line start
                lineStart = lineEnd;
                while (lineStart < len && isWhite(pstr[lineStart]))
                    lineStart++;
                if (lineStart == len)
                    break;

                i = lineStart - 1;
                lastWordEnd = 0;
                lastWordEndX = 0;
                lineWidth = 0;
            }
        }
        if (lineStart == 0)
        {
            // line is completely within bounds
            result = (&this)[0 .. 1];
        }
        else if (lineStart < len)
        {
            // append the last line
            TextLine line;
            line._str = _str[lineStart .. $];
            line._glyphs = _glyphs[lineStart .. $];
            line._charWidths = _charWidths[lineStart .. $];
            line._size = Size(lineWidth, _size.h);
            result ~= line;
        }
        return result;
    }

    /// Draw measured line at the position, applying alignment
    void draw(DrawBuf buf, Point pos, int boxWidth, const ref TextStyle style)
    {
        if (_str.length == 0)
            return; // nothing to draw - empty text

        Font font = (cast(TextStyle)style).font;
        const int height = font.height;
        const int rightCorner = pos.x + boxWidth;
        const int lineWidth = _size.w;
        if (lineWidth < boxWidth)
        {
            // align
            if (style.alignment == TextAlign.center)
            {
                pos.x += (boxWidth - lineWidth) / 2;
            }
            else if (style.alignment == TextAlign.end)
            {
                pos.x += boxWidth - lineWidth;
            }
        }
        // check visibility
        const Rect clip = buf.clipRect;
        if (clip.empty)
            return; // clipped out
        if (pos.y + height < clip.top || clip.bottom <= pos.y)
            return; // fully above or below clipping rectangle

        const bool hotkeys = style.hotkey != TextHotkey.ignore;
        bool hotkeyUnderline;
        const int baseline = font.baseline;
        const bool overline = style.decoration.line == TextDecoration.Line.overline;
        const bool lineThrough = style.decoration.line == TextDecoration.Line.lineThrough;
        const bool underline = style.decoration.line == TextDecoration.Line.underline;
        const int decorationHeight = 1;
        const int xheight = font.getCharGlyph('x').blackBoxY;
        const int overlineY = pos.y;
        const int lineThroughY = pos.y + baseline - xheight / 2 - decorationHeight;
        const int underlineY = pos.y + baseline + decorationHeight;

        const bool drawEllipsis = boxWidth < lineWidth && style.overflow != TextOverflow.clip;
        GlyphRef ellipsis = font.getCharGlyph('…');
        const ushort ellipsisW = ellipsis.widthScaled >> 6;
        const int ellipsisY = pos.y + baseline - ellipsis.originY;

        const bool ellipsisMiddle = style.overflow == TextOverflow.ellipsisMiddle;
        const int ellipsisMiddleCorner = pos.x + (boxWidth + ellipsisW) / 2;
        bool tail;
        int ellipsisPos;

        const pwidths = _charWidths.ptr;
        auto pglyphs = _glyphs.ptr;
        int pen = pos.x;
        for (size_t i; i < _str.length; i++) // `i` can mutate
        {
            if (hotkeys && _str[i] == '&')
            {
                if (style.hotkey == TextHotkey.underline)
                    hotkeyUnderline = true; // turn ON underline for hotkey
                continue; // skip '&' in hotkey
            }
            const ushort w = pwidths[i];
            if (w == 0)
                continue;

            // check glyph visibility
            if (pen > clip.right)
                break;
            const int current = pen;
            pen += w;
            if (pen + 255 < clip.left)
                continue; // far at left of clipping region

            // check overflow
            if (drawEllipsis && !tail)
            {
                if (ellipsisMiddle)
                {
                    // |text text te...xt text text|
                    //         exceeds ^ here
                    if (pen + ellipsisW > ellipsisMiddleCorner)
                    {
                        // walk to find tail width
                        int tailStart = rightCorner;
                        foreach_reverse (j; i .. _str.length)
                        {
                            if (tailStart - pwidths[j] < current + ellipsisW)
                            {
                                // jump to the tail
                                tail = true;
                                i = j;
                                pen = tailStart;
                                break;
                            }
                            else
                                tailStart -= pwidths[j];
                        }
                        ellipsisPos = (current + tailStart - ellipsisW) / 2;
                        continue;
                    }
                }
                else // at the end
                {
                    // next glyph doesn't fit, so we need the current to give a space for ellipsis
                    if (pen + ellipsisW > rightCorner)
                    {
                        ellipsisPos = current;
                        break;
                    }
                }
            }

            // draw text decoration, if exists
            if (underline || hotkeyUnderline)
            {
                buf.fillRect(Rect(current, underlineY, pen, underlineY + decorationHeight), style.color);
                // turn off underline after hotkey
                hotkeyUnderline = false;
            }
            if (overline)
                buf.fillRect(Rect(current, overlineY, pen, overlineY + decorationHeight), style.color);

            GlyphRef glyph = pglyphs[i];
            if (glyph && glyph.blackBoxX && glyph.blackBoxY) // null if space or tab
            {
                int gx = current + glyph.originX;
                if (gx + glyph.correctedBlackBoxX >= clip.left)
                {
                    buf.drawGlyph(gx, pos.y + baseline - glyph.originY, glyph, style.color);
                }
            }
            // line-through goes over text
            if (lineThrough)
                buf.fillRect(Rect(current, lineThroughY, pen, lineThroughY + decorationHeight), style.color);
        }
        if (drawEllipsis)
            buf.drawGlyph(ellipsisPos, ellipsisY, ellipsis, style.color);
    }
}

/// Represents single-line text, which can have underlined hotkeys.
/// Properties like bold or underline affects the whole text.
struct SingleLineText
{
    @property
    {
        /// Original text data
        dstring str() const
        {
            return line.str;
        }
        /// ditto
        void str(dstring s)
        {
            line.str = s;
        }

        /// True whether there is no text
        bool empty() const
        {
            return line.length == 0;
        }

        /// Size of the text after the last measure
        Size size() const
        {
            return line.size;
        }
    }

    /// Text style to adjust properties
    TextStyle style;
    private TextLine line;
    private TextStyle oldStyle;

    private bool needToMeasure() const
    {
        return line.needToMeasure || style.font !is oldStyle.font || style.tabSize != oldStyle.tabSize ||
               style.hotkey == TextHotkey.hidden && oldStyle.hotkey == TextHotkey.ignore ||
               style.hotkey == TextHotkey.ignore && oldStyle.hotkey == TextHotkey.hidden ||
               style.transform != oldStyle.transform;
    }

    /// Measure single-line text during layout
    void measure()
    {
        if (!needToMeasure)
            return;

        line.measure(style);
        oldStyle = style;
    }

    /// Draw text into buffer. Measures, if needed
    void draw(DrawBuf buf, Point pos, int boxWidth)
    {
        measure();
        line.draw(buf, pos, boxWidth, style);
    }
}

/// Represents multi-line text as is, without inner formatting.
/// Can be aligned horizontally.
struct PlainText
{
    @property
    {
        /// Original text data
        dstring str() const { return original; }
        /// ditto
        void str(dstring s)
        {
            original = s;
            _lines.clear();
            _wrappedLines.clear();
            // split by EOL char
            size_t lineStart;
            foreach (i, ch; s)
            {
                if (ch == '\n')
                {
                    _lines.put(TextLine(s[lineStart .. i]));
                    lineStart = i + 1;
                }
            }
            _lines.put(TextLine(s[lineStart .. $]));
        }

        const(TextLine[]) lines() const { return _lines.data; }

        /// True whether there is no text
        bool empty() const
        {
            return _lines.data.length == 0;
        }

        /// Size of the text after the last measure
        Size size() const { return _size; }
    }

    /// Text style to adjust properties
    TextStyle style;

    private
    {
        dstring original;
        Appender!(TextLine[]) _lines;
        Appender!(TextLine[]) _wrappedLines;
        TextStyle oldStyle;
        Size _size;

        int previousWrapWidth = -1;
    }

    private bool needToMeasure() const
    {
        if (style.font !is oldStyle.font || style.tabSize != oldStyle.tabSize ||
            style.hotkey == TextHotkey.hidden && oldStyle.hotkey == TextHotkey.ignore ||
            style.hotkey == TextHotkey.ignore && oldStyle.hotkey == TextHotkey.hidden ||
            style.transform != oldStyle.transform)
                return true;
        foreach (ref line; _lines.data)
            if (line.needToMeasure)
                return true;
        return false;
    }

    /// Measure multiline text during layout
    void measure()
    {
        if (!needToMeasure)
            return;

        Size sz;
        foreach (ref line; _lines.data)
        {
            if (line.needToMeasure)
                line.measure(style);
            sz.w = max(sz.w, line.size.w);
            sz.h += line.size.h;
        }
        _size = sz;
        oldStyle = style;
        _wrappedLines.clear();
    }

    private bool needRewrap(int width) const
    {
        return width != previousWrapWidth || _wrappedLines.data.length == 0;
    }
    /// Wrap lines within a width. Measures, if needed
    void wrapLines(int width)
    {
        if (!needRewrap(width))
            return;

        measure();
        _wrappedLines.clear();
        Size sz;
        foreach (ref line; _lines.data)
        {
            TextLine[] ls = line.wrap(width);
            foreach (ref l; ls)
            {
                sz.w = max(sz.w, l.size.w);
                sz.h += l.size.h;
            }
            _wrappedLines.put(ls);
        }
        _size = sz;
        previousWrapWidth = width;
    }

    /// Draw text into buffer. Measures, if needed
    void draw(DrawBuf buf, Point pos, int boxWidth)
    {
        measure();

        const int lineHeight = style.font.height;
        int y = pos.y;
        auto lns = _wrappedLines.data.length > _lines.data.length ? _wrappedLines.data : _lines.data;
        foreach (ref line; lns)
        {
            line.draw(buf, Point(pos.x, y), boxWidth, style);
            y += lineHeight;
        }
    }
}
