using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;

namespace Huanya.Desktop;

public static class Colors
{
    public static readonly IBrush Background = Brush.Parse("#F7F8F2"), Sidebar = Brush.Parse("#EFF1E8"), Green = Brush.Parse("#274E3D"), Ink = Brush.Parse("#273C32"), Muted = Brush.Parse("#7E887D"), Line = Brush.Parse("#E4E8DE"), Lime = Brush.Parse("#D7EDAE");
    public static IBrush Accent(Core.Kind k) => Brush.Parse(k switch { Core.Kind.Water => "#4C8198", Core.Kind.Eyes => "#8B925A", _ => "#B18462" });
    public static IBrush Wash(Core.Kind k) => Brush.Parse(k switch { Core.Kind.Water => "#EEF5F7", Core.Kind.Eyes => "#F3F4E9", _ => "#FAF0E6" });
}
// Geometry ported from BrandArtwork.swift / Views.swift; all illustrations remain project-owned vectors.
public sealed class Artwork : Control
{
    public string Drawing { get; set; } = "plant";
    public int Card
    {
        get; set;
    }
    public IBrush Color { get; set; } = Colors.Green;
    public override void Render(DrawingContext c)
    {
        base.Render(c);
        double w = Drawing == "plant" ? 180 : Drawing == "stretch" ? 80 : 24, h = Drawing == "plant" ? 220 : Drawing == "stretch" ? 110 : 24;
        using var scale = c.PushTransform(Matrix.CreateScale(Bounds.Width / w, Bounds.Height / h));
        void Path(string d, IBrush? fill, IBrush? stroke = null, double width = 1) => c.DrawGeometry(fill, stroke == null ? null : new Pen(stroke, width, lineCap: PenLineCap.Round, lineJoin: PenLineJoin.Round), Geometry.Parse(d));
        void Line(string d, string color, double width) => Path(d, null, Brush.Parse(color), width);
        void Ellipse(double x, double y, double ew, double eh, string color) => c.DrawEllipse(Brush.Parse(color), null, new Rect(x, y, ew, eh));
        if (Drawing == "plant")
        {
            Ellipse(20, 199, 145, 8, "#19203020");
            Path("M25 174 Q-8 123 34 104 Q57 146 25 174", Brush.Parse("#789573"));
            Path("M30 168 Q32 133 61 133 Q68 167 30 168", Brush.Parse("#A6B48B"));
            Line("M28 190 L32 126", "#C0CBA6", 1);
            Path("M15 176 L45 176 L40 199 L20 199Z", Brush.Parse("#D1C7A3"));
            Line("M92 139 L84 168 L70 198", "#E5DFC7", 13);
            Line("M104 141 L112 172 L124 198", "#D5D2BA", 13);
            Line("M64 201 L76 201 M122 201 L134 201", "#A2B18D", 6);
            Path("M85 89 Q96 83 109 89 L117 143 Q98 152 81 143Z", Colors.Lime);
            Line("M88 96 L68 70 L60 40 M107 96 L128 70 L137 39", "#D7EDAE", 11);
            Line("M60 40 L57 30 M137 39 L141 30", "#E2BC96", 7);
            Ellipse(86, 58, 24, 27, "#E2BC96");
            Path("M86 72 C78 46 116 46 110 65 Q91 57 86 65Z", Brush.Parse("#172E26"));
            Line("M153 87 L160 82 M155 98 L165 99 M45 80 L38 76", "#77D7EDAE", 1);
            return;
        }
        if (Drawing == "stretch")
        {
            Ellipse(29, 8, 19, 19, "#274E3D");
            Line("M39 34 L39 68", "#274E3D", 9);
            var d = Card == 2 ? "M39 39 L21 49 L12 40 M39 39 L54 47 L67 36 M39 67 L24 82 L18 102 M39 67 L51 90 L67 98" : Card == 0 ? "M39 67 L26 101 M39 67 L52 101 M39 38 L20 35 L12 19 M39 38 L58 35 L67 19" : "M39 67 L26 101 M39 67 L52 101 M39 37 L22 51 L12 46 M39 37 L55 51 L68 46";
            Line(d, "#274E3D", 5);
            if (Card == 0)
                Line("M15 61 L15 51 L11 55 M64 61 L64 51 L68 55", "#B18462", 2);
            if (Card == 1)
            {
                var pen = new Pen(Colors.Accent(Core.Kind.Stretch), 1.5, new DashStyle([3d, 3d], 0));
                c.DrawEllipse(null, pen, new Rect(1, 36, 19, 19));
                c.DrawEllipse(null, pen, new Rect(59, 36, 19, 19));
            }
            Line("M7 107 L73 107", "#55B18462", 1);
            return;
        }
        var icon = Drawing switch
        {
            "dashboard" => "M3 3H10V10H3Z M14 3H21V10H14Z M3 14H10V21H3Z M14 14H21V21H14Z",
            "bell" => "M8 19Q12 25 16 19 M4 18H20L18 14V9Q18 3 12 3Q6 3 6 9V14Z",
            "stats" => "M3 21H22 M5 18V10H8V18 M11 18V3H14V18 M17 18V7H20V18",
            "settings" => "M2 5H7 M11 5H22 M2 12H14 M18 12H22 M2 19H5 M9 19H22 M7 3H11V7H7Z M14 10H18V14H14Z M5 17H9V21H5Z",
            "water" => "M12 2C10 6 5 11 5 15A7 7 0 0 0 19 15C19 11 14 6 12 2Z",
            "eyes" => "M2 12Q12 0 22 12Q12 24 2 12Z M15 12A3 3 0 1 1 9 12A3 3 0 1 1 15 12",
            "leaf" => "M2 8Q8 11 12 5Q24 0 22 16Q8 23 2 8Z M6 10Q13 12 24 20",
            _ => "M12 7V15 M12 10L6 5 M12 10L18 5 M12 15L7 22 M12 15L17 22 M14 3A2 2 0 1 1 10 3A2 2 0 1 1 14 3"
        };
        Path(icon, Drawing == "water" ? Color : null, Color, 1.6);
    }
}

public sealed class ProgressRing : Control
{
    double progress;
    public double Progress
    {
        get => progress; set
        {
            progress = Math.Clamp(value, 0, 1);
            InvalidateVisual();
        }
    }
    public override void Render(DrawingContext context)
    {
        double r = Math.Min(Bounds.Width, Bounds.Height) / 2 - 3;
        var center = new Point(Bounds.Width / 2, Bounds.Height / 2);
        context.DrawEllipse(null, new Pen(Brush.Parse("#33FFFFFF"), 2), center, r, r);
        if (progress <= 0)
            return;
        if (progress >= .9999)
        {
            context.DrawEllipse(null, new Pen(Colors.Lime, 2.5), center, r, r);
            return;
        }
        double angle = progress * Math.PI * 2 - Math.PI / 2;
        var geometry = new StreamGeometry();
        using (var path = geometry.Open())
        {
            path.BeginFigure(new Point(center.X, center.Y - r), false);
            path.ArcTo(new Point(center.X + Math.Cos(angle) * r, center.Y + Math.Sin(angle) * r), new Size(r, r), 0, progress > .5, SweepDirection.Clockwise);
            path.EndFigure(false);
        }
        context.DrawGeometry(null, new Pen(Colors.Lime, 2.5, lineCap: PenLineCap.Round), geometry);
    }
}

public sealed class ProgressTrack : Control
{
    double fraction;
    public double Fraction { get => fraction; set { fraction = Math.Clamp(value, 0, 1); InvalidateVisual(); } }
    public IBrush Track { get; set; } = Colors.Line;
    public IBrush Fill { get; set; } = Colors.Green;
    public override void Render(DrawingContext context)
    {
        context.DrawRectangle(Track, null, new Rect(Bounds.Size), 2, 2);
        if (fraction > 0) context.DrawRectangle(Fill, null, new Rect(0, 0, Bounds.Width * fraction, Bounds.Height), 2, 2);
    }
}
