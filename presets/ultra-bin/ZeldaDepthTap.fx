texture DepthBufferTex : DEPTH;
sampler DepthTapSampler { Texture = DepthBufferTex; };

void DepthTapVS(uint vertex : SV_VertexID, out float4 position : SV_Position, out float2 uv : TEXCOORD0)
{
    uv = float2((vertex << 1) & 2, vertex & 2);
    position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

float4 DepthTapPS(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    return tex2D(DepthTapSampler, uv).rrrr;
}

technique ZeldaDepthTap
{
    pass
    {
        VertexShader = DepthTapVS;
        PixelShader = DepthTapPS;
        ColorWriteMask = 0;
    }
}
