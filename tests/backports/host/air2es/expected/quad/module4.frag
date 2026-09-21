#version 100
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
precision highp int;
void main()
{
    int g0;
    int v0 = charon_fc0;
    int v1 = ((v0) != 0 ? 1 : 0);
    g0 = v1;
    int v2 = g0;
    bool v3 = (v2) != (0);
    float v4 = charon_fc1;
    bool v5 = (charon_fc1_defined != 0);
    float v6 = (v5) ? (v4) : (0.25);
    float v7 = (v3) ? (v6) : (0.75);
    vec4 v8 = vec4((v7), (vec4(0.0)).y, (vec4(0.0)).z, (vec4(0.0)).w);
    vec4 v9 = vec4((v8).x, (v7), (v8).z, (v8).w);
    vec4 v10 = vec4((v9).x, (v9).y, (v7), (v9).w);
    vec4 v11 = vec4((v10).x, (v10).y, (v10).z, (1.0));
    gl_FragColor = v11;
}
