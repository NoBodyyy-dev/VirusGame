// Голограмма «бегущего кода» для энерго-барьеров и щитов: колонки глифов
// падают с разной скоростью, сканлайн и лёгкий глитч. Полностью процедурно,
// без текстур. Пасс без LightMode — URP рендерит его как SRPDefaultUnlit,
// то есть шейдер работает и в URP, и во встроенном конвейере.
Shader "Virus/HoloCode"
{
    Properties
    {
        _Color ("Color", Color) = (0.2, 0.6, 1, 0.55)
        _Speed ("Scroll Speed", Float) = 1.2
        _Cell ("Cell Density", Float) = 22
    }
    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" "IgnoreProjector"="True" }
        Blend SrcAlpha One      // аддитив: барьер светится, не затемняет
        ZWrite Off
        Cull Off
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            fixed4 _Color;
            float _Speed, _Cell;

            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };

            v2f vert(appdata_base v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.texcoord.xy;
                return o;
            }

            float hash(float2 p)
            {
                return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float2 cell = float2(_Cell, _Cell * 1.7);
                float colId = floor(i.uv.x * cell.x);
                // каждая колонка «падает» со своей скоростью
                float colSpeed = 0.4 + hash(float2(colId, 7.0)) * 1.6;
                float y = i.uv.y * cell.y + _Time.y * _Speed * colSpeed * 6.0;
                float2 gid = float2(colId, floor(y));
                float g = hash(gid);
                float on = step(0.45, g);                    // какие глифы горят
                // внутренний узор глифа: сегменты по трём строкам
                float2 f = float2(frac(i.uv.x * cell.x), frac(y));
                float body = step(0.16, f.x) * step(f.x, 0.84) * step(0.12, f.y) * step(f.y, 0.82);
                float seg = step(0.35, hash(gid + floor(f.y * 3.0) * 0.17));
                float glyph = on * body * seg;
                // сканлайн + мерцание
                float scan = 0.72 + 0.28 * sin((i.uv.y + _Time.y * 0.6) * 80.0);
                float flick = 0.85 + 0.15 * sin(_Time.y * 21.0 + colId * 3.1);
                fixed4 c = _Color;
                c.a *= (0.08 + glyph * 0.92) * scan * flick;   // плёнка + глифы
                c.rgb *= 1.0 + glyph * 1.8;
                return c;
            }
            ENDCG
        }
    }
    Fallback Off
}
