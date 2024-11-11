shader_type canvas_item;

uniform float x_scroll_speed : hint_range(0, 10) = 1.0;
uniform vec2 screen_size;

void fragment() {
    // Calculate the UV position based on screen width and scroll speed.
    vec2 uv = FRAGCOORD.xy / screen_size;
    uv.x *= x_scroll_speed;
    uv.x = fract(uv.x); // Repeat the texture in the x direction
    
    // Sample the texture at the modified UV
    COLOR = texture(TEXTURE, uv);
}
