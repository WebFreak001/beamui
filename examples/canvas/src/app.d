module app;

import std.functional : toDelegate;
import beamui;
import beamui.core.linalg : Vec2;
import beamui.text.shaping;
import beamui.text.simple;

int main()
{
    resourceList.setResourceDirs(
        appendPath(exePath, "resources/"),
        appendPath(exePath, "../resources/"),
    );

    GuiApp app;
    app.conf.theme = "light";
    if (!app.initialize())
        return -1;

    setStyleSheet(currentTheme, stylesheet);

    Window window = platform.createWindow("Canvas example - beamui");

    auto frame = new Panel("frame");
        auto tabs = new TabWidget;
            auto canvasPaths = new CanvasWidget;
            auto canvasBrushes = new CanvasWidget;
            auto canvasShapes = new CanvasWidget;
            auto canvasImages = new CanvasWidget;
            auto canvasText = new CanvasWidget;
            auto canvasLayers = new CanvasWidget;
            auto canvasCompositing = new CanvasWidget;
            auto canvasBlending = new CanvasWidget;
        auto settings = new Panel("settings");
            auto aaToggle = new CheckBox("Anti-aliasing");
            auto blendSettings = new Panel("blend-settings");
                auto blendModes = new ComboBox;

    frame.add(tabs, settings);
        tabs.addTab(canvasPaths.setID("PATHS"), "Paths");
        tabs.addTab(canvasBrushes.setID("BRUSHES"), "Brushes");
        tabs.addTab(canvasShapes.setID("SHAPES"), "Basic shapes");
        tabs.addTab(canvasImages.setID("IMAGES"), "Images");
        tabs.addTab(canvasText.setID("TEXT"), "Text");
        tabs.addTab(canvasLayers.setID("LAYERS"), "Layers");
        tabs.addTab(canvasCompositing.setID("COMPOSITING"), "Compositing");
        tabs.addTab(canvasBlending.setID("BLENDING"), "Blending");
        settings.add(aaToggle, blendSettings);
            blendSettings.add(new Label("Blend mode:"), blendModes);

    tabs.onTabChange ~= (string newTab, string prevTab) {
        if (newTab == "BLENDING")
            blendSettings.visibility = Visibility.visible;
        else
            blendSettings.visibility = Visibility.gone;
    };
    blendSettings.visibility = Visibility.gone;

    aaToggle.onToggle ~= (checked) { data.antialiasing = checked; };
    aaToggle.checked = true;

    blendModes.items = [__traits(allMembers, BlendMode)];
    blendModes.onSelect ~= (index) {
        assert(0 <= index && index <= BlendMode.max);
        data.blendMode = cast(BlendMode)index;
    };

    canvasPaths.onDraw = toDelegate(&paths);
    canvasBrushes.onDraw = toDelegate(&brushes);
    canvasShapes.onDraw = toDelegate(&shapes);
    canvasImages.onDraw = toDelegate(&images);
    canvasText.onDraw = toDelegate(&text);
    canvasLayers.onDraw = toDelegate(&layers);
    canvasCompositing.onDraw = toDelegate(&compositing);
    canvasBlending.onDraw = toDelegate(&blending);

    data.duck = cast(ColorDrawBuf)imageCache.get("ducky").get;
    data.icon = cast(ColorDrawBuf)imageCache.get("fileclose").get;
    assert(data.duck && data.icon);

    window.mainWidget = frame;
    window.show();
    return platform.enterMessageLoop();
}

string stylesheet = `
#frame {
    display: free;
}
TabWidget {
    width: 600px;
    height: 500px;
    left: 0;
    top: 0;
    right: 0;
    bottom: 0;
}
TabHost {
    padding: 0;
}
#settings {
    display: column;
    top: 3em;
    right: 1em;
    padding: 6px;
    background-color: rgba(255, 255, 255, 0.8);
    border: 2px solid #888;
}
#settings > * {
    align: right;
    stretch: none;
}
#blend-settings {
    display: row;
}
#blend-settings > Label {
    align: vcenter;
    stretch: none;
}
#blend-settings > ComboBox {
    min-width: 8em;
}
`;

struct AppData
{
    bool antialiasing;
    ColorDrawBuf duck;
    ColorDrawBuf icon;
    BlendMode blendMode;
}
AppData data;

void paths(Painter pr, Size sz)
{
    pr.antialias = data.antialiasing;

    // create some brushes
    const black = Brush.fromSolid(Color(0x111111));
    const opaque = Brush.fromSolid(NamedColor.dark_cyan);
    const transparent = Brush.fromSolid(Color(0x2299EE, 0x50));

    // create several paths
    Path fills, strokes, roundRect, line;
    fills
        .moveTo(100, 10)
        .lineTo(160, 198)
        .lineTo(10, 78)
        .lineTo(190, 78)
        .lineTo(40, 198)
        .close()
        .moveBy(200, 50)
        .arcBy(0,  120, 180)
        .arcBy(0, -120, 180)
        .moveBy(0, 30)
        .arcBy(0,  60, 180)
        .arcBy(0, -60, 180)
        .moveBy(150, -30)
        .arcBy(0,  120, 180)
        .arcBy(0, -120, 180)
        .moveBy(0, 30)
        .arcBy(0,  60, -180)
        .arcBy(0, -60, -180)
    ;
    strokes
        .lineBy(0, 0)
        .moveBy(50, 0)
        .lineBy(30, 0)
        .moveBy(50, 0)
        .lineBy(20, 20)
        .lineBy(20, -20)
        .lineBy(20, 20)
        .moveBy(50, 0)
        .arcBy(50, 0, 180)
        .lineBy(30, -20)
        .moveBy(50, 0)
        .cubicBy(25, 200, 50, -150, 150, 0)
        .close()
    ;
    roundRect
        .moveBy(20, 0)
        .lineBy(80, 0)
        .arcBy(20, 20, 90)
        .lineBy(0, 80)
        .arcBy(-20, 20, 90)
        .lineBy(-80, 0)
        .arcBy(-20, -20, 90)
        .lineBy(0, -80)
        .arcBy(20, -20, 90)
        .close()
    ;
    line.moveTo(30, 0).lineTo(50, 0);

    // paint stuff
    pr.scale(0.5f);
    pr.fill(fills, opaque, FillRule.nonzero);
    pr.translate(0, 250);
    pr.fill(fills, transparent, FillRule.evenodd);
    pr.scale(2);

    pr.translate(30, 220);
    pr.stroke(strokes, opaque, Pen(12, LineCap.butt, LineJoin.bevel));
    pr.stroke(strokes, black, Pen(2, LineCap.square, LineJoin.miter));
    pr.stroke(strokes, transparent, Pen(32, LineCap.round, LineJoin.round));

    pr.translate(300, -320);
    pr.fill(roundRect, transparent);
    pr.stroke(roundRect, opaque, Pen(6));

    pr.translate(60, 210.5f);
    foreach (i; 1 .. 37)
    {
        pr.stroke(line, opaque, Pen(i / 8.0f, LineCap.round));
        pr.rotate(10);
    }
}

void brushes(Painter pr, Size sz)
{
    pr.antialias = data.antialiasing;

    GradientBuilder grad;
    grad.addStop(0, NamedColor.red)
        .addStop(0.2f, NamedColor.gold)
        .addStop(0.8f, NamedColor.turquoise)
        .addStop(1, NamedColor.blue)
    ;
    const lGrad = grad.makeLinear(80, 0, 80, 160);
    const rGrad = grad.makeRadial(80, 80, 80);
    const solid = Brush.fromSolid(NamedColor.indigo);
    Brush tiles = Brush.fromPattern(data.icon);
    tiles.opacity = 0.9f;

    Path circle;
    circle.moveBy(80, 0).arcBy(0, 160, 180).arcBy(0, -160, 180);

    pr.translate(100, 40);
    pr.fill(circle, solid);
    pr.translate(200, 0);
    pr.fill(circle, tiles);
    pr.translate(-200, 200);
    pr.fill(circle, lGrad);
    pr.translate(200, 0);
    pr.fill(circle, rGrad);
}

void shapes(Painter pr, Size sz)
{
    pr.antialias = data.antialiasing;

    pr.translate(10, 10);

    pr.drawLine(0, 10, 40, 50, NamedColor.green);
    pr.translate(50, 0);
    pr.fillRect(0, 10, 30, 30, NamedColor.peru);
    pr.translate(50, 0);
    pr.fillTriangle(Vec2(20, 0), Vec2(5, 50), Vec2(40, 30), NamedColor.orange_red);
    pr.translate(80, 0);
    pr.fillCircle(0, 25, 20, NamedColor.blue_violet);

    pr.translate(250, 300);

    foreach (i; 0 .. 90)
    {
        pr.drawLine(20, 0, 120, 0, Color.black);
        pr.rotate(4);
    }
}

void images(Painter pr, Size sz)
{
    pr.antialias = data.antialiasing;

    // avatar-like image
    {
        PaintSaver sv;
        pr.save(sv);

        Path clip;
        clip.moveBy(30, 0).arcBy(0, 50, 180).arcBy(0, -50, 180);
        pr.clipIn(clip);
        pr.scale(80.0f / data.duck.width, 80.0f / data.duck.height);
        pr.drawImage(data.duck, 0, 0, 1);
    }

    pr.translate(40, 100);
    pr.drawImage(data.duck, 0, 0, 1);
    pr.translate(150, 0);
    pr.skew(40, 0);
    pr.scale(1.5f);
    pr.drawImage(data.duck, 0, 0, 0.2f);
}

void text(Painter pr, Size sz)
{
    pr.antialias = data.antialiasing;

    auto font0 = FontManager.instance.getFont(20, FontWeight.normal, false, FontFamily.sans_serif, null);
    auto font1 = FontManager.instance.getFont(16, FontWeight.normal, false, FontFamily.sans_serif, null);

    const str1 = "It is possible to draw some text using Painter directly"d;
    const str2 = "But this is too low-level"d;

    {
        TextStyle st;
        st.font = font0;
        st.color = NamedColor.purple;
        st.decoration = TextDecor(TextDecorLine.under, st.color);
        st.alignment = TextAlign.center;
        st.wrap = true;
        drawSimpleText(pr, str1, 0, 80, sz.w, st);
    }
    {
        Buf!ComputedGlyph shapingBuf;
        Buf!GlyphInstance run;
        shape(str2, shapingBuf, font1, TextTransform.none);

        const baseline = font1.baseline;
        int x;
        foreach (g; shapingBuf)
        {
            run ~= GlyphInstance(g.glyph, Point(x + g.glyph.originX, baseline - g.glyph.originY));
            x += g.width;
        }

        pr.translate((sz.w - x) / 2, 150);
        pr.drawText(run[], Color(0x444444));
    }
}

void layers(Painter pr, Size sz)
{
    pr.antialias = data.antialiasing;

    void drawWidget()
    {
        pr.fillRect(0, 0, 120, 110, Color(40, 40, 40));
        pr.fillRect(20, 20, 80, 30, Color(80, 200, 255));
        pr.fillRect(20, 60, 80, 30, Color(255, 200, 80));
    }

    pr.translate(70, 70);
    {
        PaintSaver lsv;
        pr.beginLayer(lsv, 0.9f);
        drawWidget();
    }
    pr.translate(150, 0);
    {
        PaintSaver lsv;
        pr.beginLayer(lsv, 0.5f);
        drawWidget();
    }
    pr.translate(150, 0);
    {
        PaintSaver lsv;
        pr.beginLayer(lsv, 0.1f);
        drawWidget();
    }
}

void compositing(Painter pr, Size sz)
{
    pr.antialias = data.antialiasing;

    const w = 100;
    const h = 120;
    const color = Color(180, 25, 0);
    const brush = Brush.fromSolid(Color(0, 150, 20));

    Path path;
    path.moveTo(30, 30).arcBy(40, 40, 180).arcBy(-40, -40, 180).close();

    void draw(CompositeMode mode)
    {
        pr.stroke(path, brush, Pen(5));

        PaintSaver sv, lsv;
        pr.save(sv);
        pr.clipIn(BoxI(5, 5, 95, 95));
        pr.beginLayer(lsv, 1, mode);
        pr.fillTriangle(Vec2(10, 10), Vec2(90, 70), Vec2(70, 90), color);
    }

    PaintSaver msv;
    pr.beginLayer(msv, 1);
    pr.translate(20, 20);

    with (CompositeMode)
    {
        PaintSaver sv;
        pr.save(sv);
        static foreach (mode; [sourceOver, sourceIn, sourceOut, sourceAtop])
        {
            draw(mode);
            pr.translate(w, 0);
        }
    }
    pr.translate(0, h);
    with (CompositeMode)
    {
        PaintSaver sv;
        pr.save(sv);
        static foreach (mode; [destOver, destIn, destOut, destAtop])
        {
            draw(mode);
            pr.translate(w, 0);
        }
    }
    pr.translate(0, h);
    with (CompositeMode)
    {
        static foreach (mode; [copy, xor, lighter])
        {
            draw(mode);
            pr.translate(w, 0);
        }
    }
}

void blending(Painter pr, Size sz)
{
    pr.antialias = data.antialiasing;

    const Brush bg = GradientBuilder()
        .addStop(0.0f, Color(0, 100, 200))
        .addStop(0.2f, Color(0, 0, 200))
        .addStop(0.4f, Color(200, 0, 100))
        .addStop(0.6f, Color(200, 0, 0))
        .addStop(0.8f, Color(200, 200, 0))
        .addStop(1.0f, Color(0, 200, 0))
        .makeLinear(0, 0, sz.w, 0);

    pr.paintOut(bg);

    PaintSaver sv, lsv;
    pr.save(sv);
    pr.clipIn(BoxI(9, 9, data.duck.width + 2, data.duck.height + 2));
    pr.beginLayer(lsv, 1, data.blendMode);
    pr.drawImage(data.duck, 10, 10, 1);
}
