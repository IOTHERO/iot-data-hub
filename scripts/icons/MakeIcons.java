// Draws the TiTiSwitch app icon (the mark of app/js/logo.js on a white rounded tile) as PNG:
// apple-touch-icon for the iPhone home screen (iOS takes no SVG) and the 192/512 manifest icons.
//   java scripts/icons/MakeIcons.java app
// Plain Java 2D, no libraries; the geometry follows app/icon.svg.
import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.geom.Arc2D;
import java.awt.geom.Ellipse2D;
import java.awt.geom.Path2D;
import java.awt.geom.RoundRectangle2D;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

public class MakeIcons {
    static final Color CYAN = new Color(0x00, 0xB4, 0xCD);
    static final Color ORANGE = new Color(0xF5, 0x86, 0x34);

    public static void main(String[] args) throws Exception {
        String dir = args.length > 0 ? args[0] : "app";
        write(180, true, new File(dir, "apple-touch-icon.png"));
        write(192, false, new File(dir, "icon-192.png"));
        write(512, false, new File(dir, "icon-512.png"));
    }

    static void write(int size, boolean square, File out) throws Exception {
        BufferedImage img = new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE);
        double s = size / 512.0;
        g.setColor(Color.WHITE);
        if (square) g.fillRect(0, 0, size, size);         // iOS rounds the corners itself
        else g.fill(new RoundRectangle2D.Double(0, 0, size, size, 224 * s, 224 * s));
        g.scale(s, s);
        g.translate(-57, 1);
        g.scale(0.33, 0.33);
        Path2D line = new Path2D.Double();
        double[][] pts = {{1199, 327.5}, {499.5, 327.5}, {499.5, 554.5}, {726.5, 554.5}, {726.5, 1006},
            {953.5, 1006}, {953.5, 554.5}, {1180.5, 554.5}, {1180.5, 1006}, {1444.5, 1006},
            {1444.5, 1233}, {702, 1233}};
        line.moveTo(pts[0][0], pts[0][1]);
        for (int i = 1; i < pts.length; i++) line.lineTo(pts[i][0], pts[i][1]);
        g.setColor(CYAN);
        g.setStroke(new BasicStroke(37f, BasicStroke.CAP_BUTT, BasicStroke.JOIN_MITER));
        g.draw(line);
        g.setColor(ORANGE);
        g.fill(new RoundRectangle2D.Double(783, 529, 112, 279, 112, 112));
        g.fill(new RoundRectangle2D.Double(1011, 739, 112, 279, 112, 112));
        g.setColor(Color.WHITE);
        g.fill(new Ellipse2D.Double(839 - 28, 600 - 28, 56, 56));
        g.fill(new Ellipse2D.Double(1067 - 28, 946 - 28, 56, 56));
        g.setColor(CYAN);
        g.fill(new Ellipse2D.Double(1264 - 33, 320 - 33, 66, 66));
        g.fill(new Ellipse2D.Double(647 - 32, 1233 - 32, 64, 64));
        // the signal arcs: SVG angles run clockwise from +x, Java 2D counter-clockwise
        g.setStroke(new BasicStroke(20f, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
        double[][] top = {{88, 216, 293}, {143, 214, 295}, {86, 38, 113}, {142, 34, 116}};
        for (double[] a : top) arc(g, 1264, 320, a[0], a[1], a[2]);
        g.setStroke(new BasicStroke(32f, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
        for (double r : new double[]{80, 137, 195}) arc(g, 647, 1233, r, 135, 225);
        g.dispose();
        ImageIO.write(img, "png", out);
        System.out.println(out + " " + out.length() + " bytes");
    }

    static void arc(Graphics2D g, double cx, double cy, double r, double a0, double a1) {
        g.draw(new Arc2D.Double(cx - r, cy - r, 2 * r, 2 * r, -a0, -(a1 - a0), Arc2D.OPEN));
    }
}
