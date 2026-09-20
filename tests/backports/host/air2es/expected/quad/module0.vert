#version 100
uniform highp float charon_flip;
attribute highp float a_vertex_id;
attribute highp vec2 a0_0;
attribute highp vec2 a0_8;
uniform highp float u1_0;
varying highp vec2 vary_generated_5coordDv2_f_;
void main()
{
    int v0 = int(a_vertex_id);
    vec2 v1 = a0_0;
    float v2 = u1_0;
    float v3 = (v1).x;
    float v4 = (v1).y;
    float v5 = (v3) * (v2);
    float v6 = (v4) * (v2);
    vec4 v7 = vec4((v5), (vec4(0.0)).y, (vec4(0.0)).z, (vec4(0.0)).w);
    vec4 v8 = vec4((v7).x, (v6), (v7).z, (v7).w);
    vec4 v9 = vec4((v8).x, (v8).y, (0.0), (v8).w);
    vec4 v10 = vec4((v9).x, (v9).y, (v9).z, (1.0));
    vec2 v11 = a0_8;
    gl_Position = v10;
    gl_Position.y *= charon_flip;
    vary_generated_5coordDv2_f_ = v11;
}
