"""Check aspect ratio mismatch with typical phone screens"""
# Image: 720x1640, ratio = 720/1640 = 0.4390
img_w, img_h = 720, 1640
img_ratio = img_w / img_h

# Typical phone screens (in portrait)
phones = [
    ("Pixel 6/7 (1080x2400)", 1080, 2400),
    ("Samsung S23 (1080x2340)", 1080, 2340),
    ("iPhone 14 (1170x2532)", 1170, 2532),
    ("Emulator gphone64 (1080x2400)", 1080, 2400),
    ("Generic 1080x1920", 1080, 1920),
]

print(f"Image: {img_w}x{img_h}, ratio={img_ratio:.4f}")
print()

for name, sw, sh in phones:
    screen_ratio = sw / sh
    print(f"{name}: ratio={screen_ratio:.4f}")
    
    # With BoxFit.contain, image maintains aspect ratio
    # Scale factor = min(sw/img_w, sh/img_h)
    scale = min(sw / img_w, sh / img_h)
    rendered_w = img_w * scale
    rendered_h = img_h * scale
    
    # Letterbox offset
    offset_x = (sw - rendered_w) / 2
    offset_y = (sh - rendered_h) / 2
    
    print(f"  BoxFit.contain: rendered={rendered_w:.0f}x{rendered_h:.0f}")
    print(f"  Offset: x={offset_x:.0f}, y={offset_y:.0f}")
    
    # How much the highlight would be off
    # Highlight at normalized x=0.5, y=0.5 (center)
    # Widget maps to: x=0.5*sw, y=0.5*sh
    # Image content at: x=offset_x + 0.5*rendered_w, y=offset_y + 0.5*rendered_h
    highlight_x = 0.5 * sw
    content_x = offset_x + 0.5 * rendered_w
    highlight_y = 0.5 * sh
    content_y = offset_y + 0.5 * rendered_h
    print(f"  Error at center: dx={highlight_x-content_x:.0f}px, dy={highlight_y-content_y:.0f}px")
    
    # Edge case: highlight at x=0.14 (leftish)
    h_x = 0.14 * sw
    c_x = offset_x + 0.14 * rendered_w
    print(f"  Error at x=0.14: dx={h_x-c_x:.0f}px ({abs(h_x-c_x)/sw*100:.1f}% of screen)")
    print()
