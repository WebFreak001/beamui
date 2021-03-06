/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.style.theme;

import beamui.core.config;
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.types : Result, StateFlags;
import beamui.core.units : Length;
import CSS = beamui.css.css;
import beamui.graphics.colors : Color;
import beamui.graphics.drawables : BorderStyle, Drawable;
import beamui.graphics.resources;
import beamui.layout.alignment : AlignItem, Distribution;
import beamui.style.decode_css;
import beamui.style.property;
import beamui.style.style;
import beamui.style.selector;
import beamui.style.types : SpecialCSSType;

/// Theme - a collection of widget styles
final class Theme
{
    /// Unique name of theme
    @property string name() const { return _name; }

    private
    {
        struct Bag
        {
            Style[] all;
            Style[] normal;
        }
        struct Store
        {
            Bag[string] byTag;
            Style[Selector*] map;
        }

        string _name;
        Store[string] _styles;
    }

    /// Create empty theme called `name`
    this(string name)
    {
        _name = name;
    }

    ~this()
    {
        Log.d("Destroying theme");
        foreach (ref store; _styles)
            foreach (ref bag; store.byTag)
                eliminate(bag.all);
    }

    /// Get all styles from a specific set
    Style[] getStyles(string namespace, string tag, bool normalState)
    {
        if (Store* store = namespace in _styles)
        {
            if (Bag* bag = tag in store.byTag)
                return normalState ? bag.normal : bag.all;
        }
        return null;
    }

    /// Get a style OR create it if it's not exist
    Style get(Selector* selector, string namespace)
        in(selector)
    {
        Store* store = namespace in _styles;
        if (store)
        {
            if (auto p = selector in store.map)
                return *p;
        }
        else
        {
            _styles[namespace] = Store.init;
            store = namespace in _styles;
        }
        Bag* bag = selector.type in store.byTag;
        if (!bag)
        {
            store.byTag[selector.type] = Bag.init;
            bag = selector.type in store.byTag;
        }

        auto st = new Style(*selector);
        if ((selector.specifiedState & StateFlags.normal) == selector.enabledState)
            bag.normal ~= st;
        bag.all ~= st;
        store.map[selector] = st;
        return st;
    }

    /// Print out theme stats
    void printStats() const
    {
        size_t total;
        foreach (store; _styles)
            foreach (bag; store.byTag)
                total += bag.all.length;
        Log.fd("Theme: %s, namespaces: %d, styles: %d", _name, _styles.length, total);
    }
}

private __gshared Theme _currentTheme;
/// Current theme accessor
Theme currentTheme() { return _currentTheme; }
/// Set a new theme to be current
void currentTheme(Theme theme)
{
    eliminate(_currentTheme);
    _currentTheme = theme;
}

shared static ~this()
{
    currentTheme = null;
    defaultStyleSheet = CSS.StyleSheet.init;
    defaultIsLoaded = false;
}

private __gshared CSS.StyleSheet defaultStyleSheet;
private __gshared bool defaultIsLoaded;

private alias Decoder = void function(ref StylePropertyList, const(CSS.Token)[]);

/// Load theme from file, `null` if failed
Theme loadTheme(string name)
{
    if (!name.length)
        return null;

    if (!defaultIsLoaded)
    {
        version (Windows)
            string fn = `@embedded@\themes\default.css`;
        else
            string fn = `@embedded@/themes/default.css`;
        string src = cast(string)loadResourceBytes(fn);
        assert(src.length > 0);
        defaultStyleSheet = CSS.createStyleSheet(src);
        defaultIsLoaded = true;
    }
    if (name == "default")
    {
        auto theme = new Theme(name);
        loadThemeFromCSS(theme, defaultStyleSheet, "beamui");
        return theme;
    }

    string id = (BACKEND_CONSOLE ? "console_" ~ name : name) ~ ".css";
    string filename = resourceList.getPathByID(id);
    if (!filename.length)
        return null;

    Log.d("Loading theme from file ", filename);
    string src = cast(string)loadResourceBytes(filename);
    if (!src.length)
        return null;

    auto theme = new Theme(name);
    const stylesheet = CSS.createStyleSheet(src);
    loadThemeFromCSS(theme, defaultStyleSheet, "beamui");
    loadThemeFromCSS(theme, stylesheet, "beamui");
    return theme;
}

/// Add style sheet rules from the CSS source to the theme
void setStyleSheet(Theme theme, string source, string namespace = "beamui")
{
    const stylesheet = CSS.createStyleSheet(source);
    loadThemeFromCSS(theme, stylesheet, namespace);
}

private:

void loadThemeFromCSS(Theme theme, const CSS.StyleSheet stylesheet, string ns)
    in(ns.length)
{
    Decoder[string] decoders = createDecoders();

    foreach (r; stylesheet.atRules)
    {
        applyAtRule(theme, r, ns);
    }
    foreach (r; stylesheet.rulesets)
    {
        foreach (sel; r.selectors)
        {
            applyRule(theme, decoders, sel, r.properties, ns);
        }
    }
}

void importStyleSheet(Theme theme, string resourceID, string ns)
{
    if (!resourceID)
        return;
    if (!resourceID.endsWith(".css"))
        resourceID ~= ".css";
    string filename = resourceList.getPathByID(resourceID);
    if (!filename)
        return;
    string src = cast(string)loadResourceBytes(filename);
    if (!src)
        return;
    const stylesheet = CSS.createStyleSheet(src);
    loadThemeFromCSS(theme, stylesheet, ns);
}

void applyAtRule(Theme theme, const CSS.AtRule rule, string ns)
{
    const kw = rule.keyword;
    const ps = rule.properties;

    if (kw == "import")
    {
        if (rule.content.length > 0)
        {
            const t = rule.content[0];
            if (t.type == CSS.TokenType.url)
                importStyleSheet(theme, t.text, ns);
            else
                Log.e("CSS: in @import only 'url(resource-id)' is allowed for now");
        }
        else
            Log.e("CSS: empty @import");
        if (ps.length > 0)
            Log.w("CSS: @import cannot have properties");
    }
    else
        Log.w("CSS: unknown at-rule keyword: ", kw);
}

void applyRule(Theme theme, Decoder[string] decoders, const CSS.Selector selector,
        const CSS.Property[] properties, string ns)
{
    auto style = theme.get(makeSelector(selector), ns);
    appendStyleDeclaration(style._props, decoders, properties);
}

Selector* makeSelector(const CSS.Selector selector)
{
    const(CSS.SelectorEntry)[] es = selector.entries;
    assert(es.length > 0);
    // construct selector chain
    auto sel = new Selector;
    while (true)
    {
        const combinator = makeSelectorPart(sel, es, selector.line);
        if (!combinator.isNull)
        {
            Selector* previous = sel;
            sel = new Selector;
            sel.combinator = combinator.get;
            sel.previous = previous;
        }
        else
            break;
    }
    return sel;
}

import std.typecons : Nullable, nullable;
// mutates `entries`
Nullable!(Selector.Combinator) makeSelectorPart(Selector* sel, ref const(CSS.SelectorEntry)[] entries, size_t line)
{
    Nullable!(Selector.Combinator) result;

    StateFlags specified;
    StateFlags enabled;
    // state extraction
    void applyStateFlag(StateFlags state, bool positive)
    {
        specified |= state;
        if (positive)
            enabled |= state;
    }

    bool firstEntry = true;
    Loop: foreach (i, e; entries)
    {
        string s = e.identifier;
        switch (e.type) with (CSS.SelectorEntryType)
        {
        case universal:
            if (!firstEntry)
                Log.fw("CSS(%s): * in selector must be first", line);
            break;
        case element:
            if (firstEntry)
                sel.type = s;
            else
                Log.fw("CSS(%s): element entry in selector must be first", line);
            break;
        case id:
            if (!sel.id)
                sel.id = s;
            else
                Log.fw("CSS(%s): there can be only one id in selector", line);
            break;
        case class_:
            sel.classes ~= s;
            break;
        case pseudoElement:
            if (!sel.subitem)
                sel.subitem = s;
            else
                Log.fw("CSS(%s): there can be only one pseudo element in selector", line);
            break;
        case pseudoClass:
            const positive = s[0] != '!';
            switch (positive ? s : s[1 .. $])
            {
            case "pressed":
                applyStateFlag(StateFlags.pressed, positive);
                break;
            case "focused":
                applyStateFlag(StateFlags.focused, positive);
                break;
            case "hovered":
                applyStateFlag(StateFlags.hovered, positive);
                break;
            case "selected":
                applyStateFlag(StateFlags.selected, positive);
                break;
            case "checked":
                applyStateFlag(StateFlags.checked, positive);
                break;
            case "enabled":
                applyStateFlag(StateFlags.enabled, positive);
                break;
            case "default":
                applyStateFlag(StateFlags.default_, positive);
                break;
            case "read-only":
                applyStateFlag(StateFlags.readOnly, positive);
                break;
            case "activated":
                applyStateFlag(StateFlags.activated, positive);
                break;
            case "focus-within":
                applyStateFlag(StateFlags.focusWithin, positive);
                break;
            case "root":
                sel.position = Selector.TreePosition.root;
                break;
            case "empty":
                sel.position = Selector.TreePosition.empty;
                break;
            default:
            }
            break;
        case attr:
            sel.attributes ~= Selector.Attr(s, null, Selector.Attr.Pattern.whatever);
            break;
        case attrExact:
            sel.attributes ~= Selector.Attr(s, e.str, Selector.Attr.Pattern.exact);
            break;
        case attrInclude:
            sel.attributes ~= Selector.Attr(s, e.str, Selector.Attr.Pattern.include);
            break;
        case attrDash:
            sel.attributes ~= Selector.Attr(s, e.str, Selector.Attr.Pattern.dash);
            break;
        case attrPrefix:
            sel.attributes ~= Selector.Attr(s, e.str, Selector.Attr.Pattern.prefix);
            break;
        case attrSuffix:
            sel.attributes ~= Selector.Attr(s, e.str, Selector.Attr.Pattern.suffix);
            break;
        case attrSubstring:
            sel.attributes ~= Selector.Attr(s, e.str, Selector.Attr.Pattern.substring);
            break;
        case descendant:
            result = nullable(Selector.Combinator.descendant);
            entries = entries[i + 1 .. $];
            break Loop;
        case child:
            result = nullable(Selector.Combinator.child);
            entries = entries[i + 1 .. $];
            break Loop;
        case next:
            result = nullable(Selector.Combinator.next);
            entries = entries[i + 1 .. $];
            break Loop;
        case subsequent:
            result = nullable(Selector.Combinator.subsequent);
            entries = entries[i + 1 .. $];
            break Loop;
        default:
            break;
        }
        firstEntry = false;
    }
    sel.specifiedState = specified;
    sel.enabledState = enabled;
    sel.validateAttrs();
    sel.calculateUniversality();
    sel.calculateSpecificity();
    return result;
}

void appendStyleDeclaration(ref StylePropertyList list, Decoder[string] decoders, const CSS.Property[] props)
{
    foreach (p; props)
    {
        assert(p.name.length && p.value.length);
        const twoDashes = p.name.length >= 2 && p.name[0] == '-' && p.name[1] == '-';
        if (twoDashes)
        {
            list.customProperties[p.name] = p.value;
        }
        else if (auto pdg = p.name in decoders)
        {
            (*pdg)(list, p.value);
        }
        else
            Log.fe("CSS(%d): unknown property '%s'", p.value[0].line, p.name);
    }
}

Decoder[string] createDecoders()
{
    Decoder[string] map;

    static foreach (p; PropTypes.tupleof)
    {{
        enum ptype = __traits(getMember, StyleProperty, __traits(identifier, p));
        enum cssname = getCSSName(ptype);
        map[cssname] = &decodeLonghand!(ptype, typeof(p));
    }}

    // explode shorthands
    map["margin"] = &decodeShorthandMargin;
    map["padding"] = &decodeShorthandPadding;
    map["place-content"] = &decodeShorthandPlaceContent;
    map["place-items"] = &decodeShorthandPlaceItems;
    map["place-self"] = &decodeShorthandPlaceSelf;
    map["gap"] = &decodeShorthandGap;
    map["flex-flow"] = &decodeShorthandFlexFlow;
    map["flex"] = &decodeShorthandFlex;
    map["grid-area"] = &decodeShorthandGridArea;
    map["grid-row"] = &decodeShorthandGridRow;
    map["grid-column"] = &decodeShorthandGridColumn;
    map["background"] = &decodeShorthandDrawable;
    map["border"] = &decodeShorthandBorder;
    map["border-color"] = &decodeShorthandBorderColors;
    map["border-style"] = &decodeShorthandBorderStyle;
    map["border-width"] = &decodeShorthandBorderWidth;
    map["border-top"] = &decodeShorthandBorderTop;
    map["border-right"] = &decodeShorthandBorderRight;
    map["border-bottom"] = &decodeShorthandBorderBottom;
    map["border-left"] = &decodeShorthandBorderLeft;
    map["border-radius"] = &decodeShorthandBorderRadii;
    map["text-decoration"] = &decodeShorthandTextDecor;
    map["transition"] = &decodeShorthandTransition;

    return map;
}

alias P = StyleProperty;

void decodeLonghand(P ptype, T)(ref StylePropertyList list, const(CSS.Token)[] tokens)
    in(tokens.length)
{
    if (setMeta(list, tokens, ptype))
        return;

    enum specialType = getSpecialCSSType(ptype);
    static if (specialType != SpecialCSSType.none)
        Result!T result = decode!specialType(tokens);
    else
        Result!T result = decode!T(tokens);

    if (result.err)
        return;

    if (!sanitizeProperty!ptype(result.val))
    {
        logInvalidValue(tokens);
        return;
    }

    list.set(ptype, result.val);
}

bool setMeta(ref StylePropertyList list, const CSS.Token[] tokens, P[] ps...)
{
    if (tokens.length == 1 && tokens[0].type == CSS.TokenType.ident)
    {
        if (tokens[0].text == "inherit")
        {
            foreach (p; ps)
                list.inherit(p);
            return true;
        }
        if (tokens[0].text == "initial")
        {
            foreach (p; ps)
                list.initialize(p);
            return true;
        }
    }
    return false;
}

void setOrInitialize(P ptype, T)(ref StylePropertyList list, const CSS.Token[] tokens, bool initial, ref T v)
{
    if (initial)
    {
        list.initialize(ptype);
        return;
    }
    if (!sanitizeProperty!ptype(v))
    {
        logInvalidValue(tokens);
        list.initialize(ptype);
        return;
    }
    list.set(ptype, v);
}

void decodeShorthandPair(T, P first, P second)(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, first, second))
        return;

    if (auto res = decodePair!T(tokens))
    {
        setOrInitialize!first(list, tokens, false, res.val[0]);
        setOrInitialize!second(list, tokens, false, res.val[1]);
    }
}
void decodeShorthandInsets(P top, P right, P bottom, P left)(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, top, right, bottom, left))
        return;

    auto arr = decodeInsets(tokens);
    if (arr.length > 0)
    {
        // [all], [vertical horizontal], [top horizontal bottom], [top right bottom left]
        setOrInitialize!top(list, tokens, false, arr[0]);
        setOrInitialize!right(list, tokens, false, arr[arr.length > 1 ? 1 : 0]);
        setOrInitialize!bottom(list, tokens, false, arr[arr.length > 2 ? 2 : 0]);
        setOrInitialize!left(list, tokens, false, arr[arr.length == 4 ? 3 : arr.length == 1 ? 0 : 1]);
    }
}
void decodeShorthandBorderSide(P width, P style, P color)(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, width, style, color))
        return;

    if (auto res = decodeBorder(tokens))
    {
        setOrInitialize!width(list, tokens, res.val[0].err, res.val[0].val);
        setOrInitialize!style(list, tokens, false, res.val[1]);
        setOrInitialize!color(list, tokens, res.val[2].err, res.val[2].val);
    }
}
void decodeShorthandGridLine(P start, P end)(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, start, end))
        return;

    if (auto res = decodeGridArea(tokens))
    {
        const ln = res.val;
        setOrInitialize!start(list, tokens, false, ln);
        setOrInitialize!end(list, tokens, false, ln);
    }
}

void decodeShorthandMargin(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandInsets!(P.marginTop, P.marginRight, P.marginBottom, P.marginLeft)(list, tokens);
}
void decodeShorthandPadding(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandInsets!(P.paddingTop, P.paddingRight, P.paddingBottom, P.paddingLeft)(list, tokens);
}

void decodeShorthandPlaceContent(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandPair!(Distribution, P.alignContent, P.justifyContent)(list, tokens);
}
void decodeShorthandPlaceItems(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandPair!(AlignItem, P.alignItems, P.justifyItems)(list, tokens);
}
void decodeShorthandPlaceSelf(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandPair!(AlignItem, P.alignSelf, P.justifySelf)(list, tokens);
}
void decodeShorthandGap(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandPair!(Length, P.rowGap, P.columnGap)(list, tokens);
}

void decodeShorthandDrawable(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.bgColor, P.bgImage))
        return;

    if (auto res = decodeBackground(tokens))
    {
        Result!Color color = res.val[0];
        Result!Drawable image = res.val[1];
        setOrInitialize!(P.bgColor)(list, tokens, color.err, color.val);
        setOrInitialize!(P.bgImage)(list, tokens, image.err, image.val);
    }
}

void decodeShorthandFlexFlow(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.flexDirection, P.flexWrap))
        return;

    if (auto res = decodeFlexFlow(tokens))
    {
        setOrInitialize!(P.flexDirection)(list, tokens, res.val[0].err, res.val[0].val);
        setOrInitialize!(P.flexWrap)(list, tokens, res.val[1].err, res.val[1].val);
    }
}
void decodeShorthandFlex(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.flexGrow, P.flexShrink, P.flexBasis))
        return;

    if (auto res = decodeFlex(tokens))
    {
        setOrInitialize!(P.flexGrow)(list, tokens, false, res.val[0]);
        setOrInitialize!(P.flexShrink)(list, tokens, false, res.val[1]);
        setOrInitialize!(P.flexBasis)(list, tokens, false, res.val[2]);
    }
}

void decodeShorthandGridArea(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.gridRowStart, P.gridRowEnd, P.gridColumnStart, P.gridColumnEnd))
        return;

    if (auto res = decodeGridArea(tokens))
    {
        const ln = res.val;
        setOrInitialize!(P.gridRowStart)(list, tokens, false, ln);
        setOrInitialize!(P.gridRowEnd)(list, tokens, false, ln);
        setOrInitialize!(P.gridColumnStart)(list, tokens, false, ln);
        setOrInitialize!(P.gridColumnEnd)(list, tokens, false, ln);
    }
}
void decodeShorthandGridRow(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandGridLine!(P.gridRowStart, P.gridRowEnd)(list, tokens);
}
void decodeShorthandGridColumn(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandGridLine!(P.gridColumnStart, P.gridColumnEnd)(list, tokens);
}

void decodeShorthandBorder(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens,
            P.borderTopWidth, P.borderTopStyle, P.borderTopColor,
            P.borderRightWidth, P.borderRightStyle, P.borderRightColor,
            P.borderBottomWidth, P.borderBottomStyle, P.borderBottomColor,
            P.borderLeftWidth, P.borderLeftStyle, P.borderLeftColor))
        return;

    if (auto res = decodeBorder(tokens))
    {
        auto wv = res.val[0].val;
        auto sv = res.val[1];
        auto cv = res.val[2].val;
        const wreset = res.val[0].err;
        const creset = res.val[2].err;
        setOrInitialize!(P.borderTopWidth)(list, tokens, wreset, wv);
        setOrInitialize!(P.borderTopStyle)(list, tokens, false, sv);
        setOrInitialize!(P.borderTopColor)(list, tokens, creset, cv);
        setOrInitialize!(P.borderRightWidth)(list, tokens, wreset, wv);
        setOrInitialize!(P.borderRightStyle)(list, tokens, false, sv);
        setOrInitialize!(P.borderRightColor)(list, tokens, creset, cv);
        setOrInitialize!(P.borderBottomWidth)(list, tokens, wreset, wv);
        setOrInitialize!(P.borderBottomStyle)(list, tokens, false, sv);
        setOrInitialize!(P.borderBottomColor)(list, tokens, creset, cv);
        setOrInitialize!(P.borderLeftWidth)(list, tokens, wreset, wv);
        setOrInitialize!(P.borderLeftStyle)(list, tokens, false, sv);
        setOrInitialize!(P.borderLeftColor)(list, tokens, creset, cv);
    }
}
void decodeShorthandBorderColors(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.borderTopColor, P.borderRightColor, P.borderBottomColor, P.borderLeftColor))
        return;

    if (auto res = decode!Color(tokens))
    {
        auto v = res.val;
        setOrInitialize!(P.borderTopColor)(list, tokens, false, v);
        setOrInitialize!(P.borderRightColor)(list, tokens, false, v);
        setOrInitialize!(P.borderBottomColor)(list, tokens, false, v);
        setOrInitialize!(P.borderLeftColor)(list, tokens, false, v);
    }
}
void decodeShorthandBorderStyle(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.borderTopStyle, P.borderRightStyle, P.borderBottomStyle, P.borderLeftStyle))
        return;

    if (auto res = decode!BorderStyle(tokens))
    {
        auto v = res.val;
        setOrInitialize!(P.borderTopStyle)(list, tokens, false, v);
        setOrInitialize!(P.borderRightStyle)(list, tokens, false, v);
        setOrInitialize!(P.borderBottomStyle)(list, tokens, false, v);
        setOrInitialize!(P.borderLeftStyle)(list, tokens, false, v);
    }
}
void decodeShorthandBorderWidth(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandInsets!(P.borderTopWidth, P.borderRightWidth, P.borderBottomWidth, P.borderLeftWidth)(list, tokens);
}
void decodeShorthandBorderTop(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandBorderSide!(P.borderTopWidth, P.borderTopStyle, P.borderTopColor)(list, tokens);
}
void decodeShorthandBorderRight(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandBorderSide!(P.borderRightWidth, P.borderRightStyle, P.borderRightColor)(list, tokens);
}
void decodeShorthandBorderBottom(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandBorderSide!(P.borderBottomWidth, P.borderBottomStyle, P.borderBottomColor)(list, tokens);
}
void decodeShorthandBorderLeft(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandBorderSide!(P.borderLeftWidth, P.borderLeftStyle, P.borderLeftColor)(list, tokens);
}
void decodeShorthandBorderRadii(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandInsets!(P.borderTopLeftRadius, P.borderTopRightRadius,
            P.borderBottomLeftRadius, P.borderBottomRightRadius)(list, tokens);
}

void decodeShorthandTextDecor(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.textDecorLine, P.textDecorColor, P.textDecorStyle))
        return;

    if (auto res = decodeTextDecor(tokens))
    {
        auto line = res.val[0];
        auto color = res.val[1];
        auto style = res.val[2];
        setOrInitialize!(P.textDecorLine)(list, tokens, false, line);
        setOrInitialize!(P.textDecorColor)(list, tokens, color.err, color.val);
        setOrInitialize!(P.textDecorStyle)(list, tokens, style.err, style.val);
    }
}

void decodeShorthandTransition(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens,
            P.transitionProperty, P.transitionDuration,
            P.transitionTimingFunction, P.transitionDelay))
        return;

    if (auto res = decodeTransition(tokens))
    {
        auto prop = res.val[0];
        auto dur = res.val[1];
        auto tfunc = res.val[2];
        auto delay = res.val[3];
        setOrInitialize!(P.transitionProperty)(list, tokens, prop.err, prop.val);
        setOrInitialize!(P.transitionDuration)(list, tokens, dur.err, dur.val);
        setOrInitialize!(P.transitionTimingFunction)(list, tokens, tfunc.err, tfunc.val);
        setOrInitialize!(P.transitionDelay)(list, tokens, delay.err, delay.val);
    }
}
