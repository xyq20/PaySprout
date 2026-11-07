using System;
using System.Windows;
using System.Windows.Media;

namespace PaySprout;
public sealed class SproutView : FrameworkElement
{
    public double Progress { get; set; }
    public bool Charging { get; set; }
    private bool animate;
    public bool Animate { get => animate; set { if (animate == value) return; animate=value; if (value) CompositionTarget.Rendering += RenderFrame; else CompositionTarget.Rendering -= RenderFrame; InvalidateVisual(); } }
    public SproutView() { Unloaded += (_,_) => Animate=false; }
    private void RenderFrame(object? sender,EventArgs e) => InvalidateVisual();
    private static SolidColorBrush Color(string color) => (SolidColorBrush)new BrushConverter().ConvertFromString(color)!;
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        dc.PushTransform(new ScaleTransform(ActualWidth/100,ActualHeight/100));
        var time=Animate ? DateTime.Now.TimeOfDay.TotalSeconds : 0;
        var sway=Animate ? Math.Sin(time*2)*2 : 0;
        if (Charging) {
            var flame=Geometry.Parse("M 20,80 L 12,57 27,63 20,35 36,47 38,15 49,34 59,5 65,40 82,24 79,58 94,44 86,80 Z");
            dc.DrawGeometry(Color("#FFDF64"),null,flame);
            dc.DrawGeometry(null,new Pen(Color("#97AFE5"),2),Geometry.Parse("M 15,35 L 11,52 19,49 13,72 M 85,30 L 81,47 89,44 83,70"));
        }
        dc.DrawEllipse(Color("#DDE5DA"),null,new Point(50,92),29,4);
        dc.PushTransform(new RotateTransform(sway,50,82));
        var stem=Color(Charging ? "#B97E18" : "#47724F");
        dc.DrawLine(new Pen(stem,4),new Point(50,76),new Point(50,32));
        dc.DrawGeometry(Color(Charging ? "#FFEEA1" : "#8EBE80"),null,Geometry.Parse("M 50,57 C 19,60 18,30 23,28 C 43,28 51,40 50,57 Z"));
        dc.DrawGeometry(Color(Charging ? "#FFE275" : "#659961"),null,Geometry.Parse("M 50,45 C 48,23 67,17 79,20 C 82,40 65,48 50,45 Z"));
        if (Progress >= .25) dc.DrawGeometry(Color(Charging ? "#FFE275" : "#A8C991"),null,Geometry.Parse("M 50,68 C 53,50 70,49 78,53 C 72,69 59,71 50,68 Z"));
        if (Progress >= .85) {
            if (Progress >= 1) { for(int i=0;i<6;i++) { var angle=i*Math.PI/3; dc.DrawEllipse(Color("#F3B9CE"),null,new Point(50+Math.Cos(angle)*10,25+Math.Sin(angle)*10),8,8); } dc.DrawEllipse(Color("#FFDF78"),null,new Point(50,25),7,7); }
            else dc.DrawEllipse(Color("#F2BCCB"),null,new Point(50,25),6,9);
        }
        dc.Pop();
        dc.DrawGeometry(Color(Charging ? "#E6B94A" : "#C4D6AB"),null,Geometry.Parse("M 25,69 L 75,69 69,90 Q 50,97 31,90 Z"));
        dc.DrawRoundedRectangle(Color(Charging ? "#F3D46E" : "#D6E1C1"),null,new Rect(22,65,56,9),4,4);
        var face=Color("#42513D");
        if (Progress <= 0) { dc.DrawLine(new Pen(face,2),new Point(39,79),new Point(44,79)); dc.DrawLine(new Pen(face,2),new Point(56,79),new Point(61,79)); }
        else { dc.DrawEllipse(face,null,new Point(41,79),1.8,2); dc.DrawEllipse(face,null,new Point(59,79),1.8,2); }
        dc.DrawGeometry(null,new Pen(face,1.5),Geometry.Parse("M 46,84 Q 50,88 54,84"));
        dc.Pop();
    }
}

public sealed class FireworksView : FrameworkElement
{
    private DateTime? started;
    private bool animate;
    public bool Animate { get => animate; set { if (animate == value) return; animate=value; Unsubscribe(); if (animate && started != null) CompositionTarget.Rendering += Frame; InvalidateVisual(); } }
    public void Play() { started=DateTime.Now; Unsubscribe(); if (animate) CompositionTarget.Rendering += Frame; InvalidateVisual(); }
    public void Stop() { started=null; Unsubscribe(); InvalidateVisual(); }
    private void Unsubscribe() => CompositionTarget.Rendering -= Frame;
    private void Frame(object? sender,EventArgs e) { if (started != null && (DateTime.Now-started.Value).TotalSeconds >= 12) Stop(); else InvalidateVisual(); }
    public FireworksView() { Unloaded += (_,_) => Stop(); }
    protected override void OnRender(DrawingContext dc)
    {
        if (started == null) return;
        var time=animate ? (DateTime.Now-started.Value).TotalSeconds : 1;
        if (time < 0 || time >= 12) return;
        var colors=new[]{"#FFABCF","#CCADFF","#FFD180","#99D4FF"};
        for(int burst=0;burst<10;burst++) {
            var age=time-burst*.8; if(age<0 || age>2.1) continue;
            var p=Math.Min(1,age/1.8); var radius=Math.Min(ActualWidth,ActualHeight)*.23*(1-Math.Pow(1-p,2));
            var center=new Point(ActualWidth*(.15+(burst*3%8)/11d),ActualHeight*(.16+(burst*5%6)/14d));
            var brush=(SolidColorBrush)new BrushConverter().ConvertFromString(colors[burst%4])!; brush.Opacity=Math.Max(0,1-p);
            for(int i=0;i<28;i++) { var angle=i/28d*Math.PI*2; var distance=radius*(i%2==0 ? 1 : .72); var point=new Point(center.X+Math.Cos(angle)*distance,center.Y+Math.Sin(angle)*distance+p*p*20); var previous=new Point(center.X+Math.Cos(angle)*distance*.78,center.Y+Math.Sin(angle)*distance*.78+p*p*16); dc.DrawLine(new Pen(brush,1.5),previous,point); dc.DrawEllipse(brush,null,point,1.7,1.7); }
        }
    }
}
