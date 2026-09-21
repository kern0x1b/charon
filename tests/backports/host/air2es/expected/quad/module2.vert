#version 100
uniform highp float charon_flip;
uniform highp float charon_instance;
attribute highp vec2 vin0;
attribute highp vec2 vin1;
attribute highp vec4 vin2;
uniform highp float u1_0;
varying highp vec2 vary_generated_5coordDv2_f_;
varying highp vec4 vary_generated_5shadeDv4_f_;
void main()
{
    float v0 = u1_0;
    float v1 = (vin0).x;
    float v2 = (vin0).y;
    float v3 = (v1) * (v0);
    float v4 = (v2) * (v0);
    vec4 v5 = vec4((v3), (vec4(0.0)).y, (vec4(0.0)).z, (vec4(0.0)).w);
    vec4 v6 = vec4((v5).x, (v4), (v5).z, (v5).w);
    vec4 v7 = vec4((v6).x, (v6).y, (0.0), (v6).w);
    vec4 v8 = vec4((v7).x, (v7).y, (v7).z, (1.0));
    float v9 = float(int(charon_instance));
    float v10 = (v9) * (0.5);
    float v11 = (vin1).x;
    float v12 = (v11) + (v10);
    vec2 v13 = vec2((v12), (vin1).y);
    gl_Position = v8;
    gl_Position.y *= charon_flip;
    vary_generated_5coordDv2_f_ = v13;
    vary_generated_5shadeDv4_f_ = vin2;
}
