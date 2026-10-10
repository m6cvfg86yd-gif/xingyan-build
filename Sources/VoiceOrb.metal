//
//  语音球 —— GPU 着色器（iOS 17+ 的 SwiftUI ShaderLibrary 用）
//
//  这一版按用户给的提示词重写：
//    「晶莹剔透的 3D 玻璃球悬浮在深色背景中，球体内部有柔和的呼吸流动，
//      表面带有低饱和度的柔和高光，整体呈现出液态金属在里面流动的质感，
//      配合半透明的次表面散射效果」
//
//  对应到着色器里的四件事：
//    ① 晶莹玻璃球：球本身**不染色**，只做折射 + 菲涅尔边缘 + 一道很细的亮圈；
//    ② 内部液态金属：域扭曲的流场 + 两层细纹（银白为主，带一丝极淡的品牌色），
//       整体按一个很慢的正弦"呼吸"，音量越大流动越亮；
//    ③ 低饱和柔和高光：两个**又宽又软**的波瓣（指数 46 / 22），不是针尖亮斑，
//       颜色基本是中性白（只在最外层掺一点冷色）；
//    ④ 次表面散射：靠边的像素往里"透光"，边缘泛出一层很淡的柔光，
//       看着像半透明材质而不是实心玻璃。
//
//  接口和上一版完全一致（time, w, h, c1…c4, amp, glass, radius），
//  所以 Swift 那边一行都不用改。
//
#include <metal_stdlib>
using namespace metal;

static float sat(float x) { return clamp(x, 0.0, 1.0); }

/* 便宜的流动噪声：几层正弦叠出来的 0…1 场（GPU 上比 hash 噪声快，够柔） */
static float orbFlow(float2 p, float t) {
    float v = 0.0;
    v += sin(p.x * 1.7 + t * 0.55) * sin(p.y * 2.1 - t * 0.42);
    v += 0.55 * sin(p.x * 3.1 - p.y * 1.4 + t * 0.80);
    v += 0.35 * sin((p.x + p.y) * 4.3 + t * 1.15);
    return sat(v * 0.5 + 0.5);
}

/* 液态金属的细纹：在流场里再切一层条纹，慢速漂移 */
static float orbVeins(float2 p, float t) {
    float f = orbFlow(p * 1.6, t * 0.8);
    float band = sin((p.x * 2.2 + p.y * 1.3 + f * 3.4) * 3.14159 + t * 0.9);
    return sat(band * 0.5 + 0.5);
}

[[ stitchable ]] half4 voiceOrb(float2 pos, half4 inColor,
                                float time, float w, float h,
                                half4 c1, half4 c2, half4 c3, half4 c4,
                                float amp, float glass, float radius)
{
    float2 size = float2(w, h);
    float2 uv = (pos - size * 0.5) / (size.x * 0.5);      // -1 … 1

    /* 品牌色只用来"点一点"：整体是银白，压到很低的饱和度 */
    float3 brand = normalize(float3(c1.rgb) + float3(c2.rgb) + float3(c3.rgb) + float3(c4.rgb)
                             + float3(0.001));
    float3 tintSoft = mix(float3(1.0), brand, 0.26);

    /* 球缘的有机起伏：玻璃球要"圆"，所以比上一版收敛很多 */
    float theta = atan2(uv.y, uv.x);
    float deform = (sin(theta * 2.0 + time * 0.9) * 0.5
                  + cos(theta * 3.0 - time * 1.3) * 0.30
                  + sin(theta * 5.0 + time * 1.7) * 0.20) * (0.020 + amp * 0.045);
    float R = radius * (1.0 + deform);

    /* 呼吸：一个很慢的整体脉动（吸—呼），球会轻轻胀一下 */
    float breath = smoothstep(0.0, 1.0, 0.5 + 0.5 * sin(time * 0.85));
    float r = length(uv) / max(R, 0.001) / (0.985 + breath * 0.030);

    /* ================= 球外：深色背景上的一圈柔光 + 一点落影 ================= */
    if (r > 1.0) {
        float d = clamp((r - 1.0) / 0.85, 0.0, 1.0);
        float halo = pow(1.0 - d, 2.6);
        float3 haloCol = tintSoft * halo * (0.16 + amp * 0.20);

        /* 球下方一点落影，让球"浮"在深色底上 */
        float dy = uv.y - 1.02;
        float shadow = exp(-(uv.x * uv.x * 2.0 + dy * dy * 30.0)) * 0.34;

        float3 out3 = haloCol - float3(shadow * 0.55);
        float a = clamp(max(halo * 0.60, shadow * 0.50), 0.0, 1.0);
        return half4(half3(max(out3, 0.0)), half(a));
    }

    /* ================= 球面法线（折射 / 高光 / 散射都靠它） ================= */
    float3 N = normalize(float3(uv / max(R, 0.001), sqrt(max(0.0004, 1.0 - r * r))));

    /* ================= 球里：液态金属 =================
       域扭曲：拿一层流场去推坐标，再在上面切细纹 —— 看着就是"里面有液体在慢慢搅" */
    float2 sp = uv / max(R, 0.001);
    float2 q = sp * 1.35;
    q += 0.45 * float2(orbFlow(q * 0.9 + float2(0.0, time * 0.12), time * 0.50),
                       orbFlow(q * 0.9 + float2(4.7, -time * 0.10), time * 0.42)) - 0.22;

    /* 折射：中间几乎不折、越靠边折得越狠（球面透镜），球缘把里面的纹路压出环状 */
    float bend = pow(1.0 - clamp(N.z, 0.0, 1.0), 1.35);
    float2 rp = q - N.xy * (0.22 * clamp(glass, 0.30, 1.40) * (0.35 + (1.0 - r)));

    float v1 = orbVeins(rp, time);
    float v2 = orbVeins(rp * 1.9 + float2(3.1, -1.4), time * 1.25);

    /* 呼吸：流动的强弱慢慢起伏（不是整颗忽明忽暗，是"里面在动"） */
    float breathAmp = 0.62 + 0.38 * sin(time * 0.75 + rp.x * 0.6);
    v1 = sat(mix(0.5, v1, breathAmp));

    /* 注意：这个变量不能叫 metal —— 会和 metal 命名空间撞名 */
    float3 liquid = mix(float3(0.26), float3(0.96), v1);         // 银白
    liquid = mix(liquid, liquid * 1.22 + 0.05, v2 * 0.42);       // 叠一层更细的纹
    liquid *= tintSoft;                                           // 极淡的品牌色

    /* 容器感：四周略压暗、中间那团金属更亮 */
    float innerMask = smoothstep(1.0, 0.15, r);
    float3 body = liquid * (0.44 + 0.72 * innerMask);

    /* ================= 次表面散射：靠边往里透光 ================= */
    float sss = pow(1.0 - clamp(N.z, 0.0, 1.0), 1.25);
    body += tintSoft * sss * (0.30 + amp * 0.26);
    body += float3(0.85, 0.90, 1.0) * sss * 0.16;

    /* ================= 低饱和度的柔和高光（两个又宽又软的波瓣） ================= */
    float3 L1 = normalize(float3(-0.42, -0.58, 0.70));            // 主光：左上
    float3 L2 = normalize(float3(0.55, -0.28, 0.79));             // 补光：右上
    float3 V  = float3(0.0, 0.0, 1.0);
    float s1 = pow(clamp(dot(N, normalize(L1 + V)), 0.0, 1.0), 46.0);
    float s2 = pow(clamp(dot(N, normalize(L2 + V)), 0.0, 1.0), 22.0);
    body += float3(1.0, 0.99, 0.97) * (s1 * 0.58 + s2 * 0.20);

    /* ================= 玻璃的边：菲涅尔亮环 + 一道很细的亮圈 ================= */
    float fres = pow(1.0 - clamp(N.z, 0.0, 1.0), 2.0);
    body += float3(0.80, 0.88, 1.0) * fres * 0.40;
    body += float3(0.92, 0.96, 1.0) * smoothstep(0.960, 1.0, r) * 0.55;

    /* 说话越大声，里面那团金属越亮（呼吸更明显） */
    body *= (0.92 + amp * 0.45);

    /* 边缘柔和收进去 */
    float edge = smoothstep(1.0, 0.94, r);
    return half4(half3(max(body, 0.0)) * half(edge), half(edge));
}
