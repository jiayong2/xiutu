shader_type canvas_item;
render_mode unshaded;

uniform sampler2D explored_mask : filter_linear, repeat_disable;
uniform vec4 fog_color : source_color;

void fragment() {
	float explored = texture(explored_mask, UV).r;
	COLOR = vec4(fog_color.rgb, 1.0 - explored);
}
