Shader "Sizimityper/BlinkingLED"
{
    Properties
    {
        // テクスチャ
        _MainTex ("メインテクスチャ", 2D) = "white" {}
        _SubTex ("サブテクスチャ (黒=オフ)", 2D) = "black" {}

        // 発光制御
        [HDR] _Color ("LEDカラー", Color) = (1, 0.2, 0, 1)
        _EmissionIntensity ("発光強度", Float) = 1.0
        _MinBrightness ("最小輝度", Range(0, 1)) = 0.0

        // 点滅制御
        [Toggle] _BlinkMode ("点滅モード (0=ステップ, 1=サイン)", Float) = 0
        _BlinkSpeed ("点滅速度 (Hz)", Float) = 1.0
        _DutyCycle ("デューティサイクル", Range(0, 1)) = 0.5
        [Toggle] _InvertBlink ("点滅反転 (NOT)", Float) = 0

        // LEDマスク
        [Toggle] _MaskMode ("マスクモード (0=グリッド, 1=同心円)", Float) = 0
        _LedDensity ("LED密度 (グリッド)", Int) = 8
        _RingCount ("リング数 (同心円)", Int) = 5
        _DotSize ("ドットサイズ", Range(0, 1)) = 0.4
        _DotSoftness ("ドットのぼかし", Range(0, 1)) = 0.05

        // パララックス
        _ParallaxHeight ("パララックス高さ", Float) = 0.02
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 viewDirTS : TEXCOORD1;
                UNITY_FOG_COORDS(2)
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _SubTex;

            float4 _Color;
            float _EmissionIntensity;
            float _MinBrightness;

            float _BlinkMode;
            float _BlinkSpeed;
            float _DutyCycle;
            float _InvertBlink;

            float _MaskMode;
            int _LedDensity;
            int _RingCount;
            float _DotSize;
            float _DotSoftness;

            float _ParallaxHeight;

            // ----- LEDマスク計算 -----
            float calcGridMask(float2 uv)
            {
                float2 cell = frac(uv * _LedDensity);
                float dist = length(cell - 0.5);
                return smoothstep(_DotSize, _DotSize - _DotSoftness, dist);
            }

            float calcConcentricMask(float2 uv)
            {
                float2 centered = uv - 0.5;
                float r = length(centered);
                float theta = atan2(centered.y, centered.x);

                float ringFloat = r * _RingCount * 2.0;
                float ringIdx = floor(ringFloat);
                float ringFrac = frac(ringFloat);

                float dotsInRing = max(1.0, round(max(1.0, ringIdx) * UNITY_PI));
                float dotPhase = frac(theta / (UNITY_TWO_PI) * dotsInRing + 0.5);

                float distR = ringFrac - 0.5;
                float distA = dotPhase - 0.5;

                float cellArc = UNITY_TWO_PI * (ringIdx + 0.5) / (_RingCount * 2.0) / dotsInRing;
                float cellRadial = 1.0 / (_RingCount * 2.0);
                float aspectRatio = cellArc / cellRadial;
                aspectRatio = max(aspectRatio, 0.001);

                float2 distVec = float2(distA * aspectRatio, distR);
                float dist = length(distVec);

                return smoothstep(_DotSize, _DotSize - _DotSoftness, dist);
            }

            float calcMask(float2 uv)
            {
                return _MaskMode > 0.5 ? calcConcentricMask(uv) : calcGridMask(uv);
            }

            // ----- 点滅計算 -----
            float calcBlink()
            {
                float phase = frac(_Time.y * _BlinkSpeed);
                float blink;

                if (_BlinkMode > 0.5)
                {
                    blink = sin(phase * UNITY_TWO_PI) * 0.5 + 0.5;
                }
                else
                {
                    blink = step(phase, _DutyCycle);
                }

                blink = _InvertBlink > 0.5 ? 1.0 - blink : blink;

                return blink;
            }

            // ----- 頂点シェーダー -----
            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);

                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                float3 worldViewDir = normalize(_WorldSpaceCameraPos - worldPos);

                float3 worldNormal = UnityObjectToWorldNormal(v.normal);
                float3 worldTangent = normalize(mul((float3x3)unity_ObjectToWorld, v.tangent.xyz));
                float3 worldBinormal = cross(worldNormal, worldTangent) * v.tangent.w;

                float3x3 tbn = float3x3(worldTangent, worldBinormal, worldNormal);
                o.viewDirTS = mul(tbn, worldViewDir);

                UNITY_TRANSFER_FOG(o, o.pos);
                return o;
            }

            // ----- フラグメントシェーダー -----
            fixed4 frag(v2f i) : SV_Target
            {
                float3 viewDir = normalize(i.viewDirTS);
                float2 uv = i.uv;

                float preMask = calcMask(uv);
                float2 uvOffset = viewDir.xy / viewDir.z * preMask * _ParallaxHeight;
                uv += uvOffset;

                float mask = calcMask(uv);
                float blink = calcBlink();

                float4 tex = blink > 0.5 ? tex2D(_MainTex, uv) : tex2D(_SubTex, uv);
                float brightness = lerp(_MinBrightness, 1.0, blink);

                float4 col;
                col.rgb = tex.rgb * _Color.rgb * mask * brightness * _EmissionIntensity;
                col.a = 1.0;

                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
    FallBack "Unlit/Texture"
}

