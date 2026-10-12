//
//  CloudGlass.metal
//  Облачко прослушивания целиком: стеклянная пилюля и скрученная лента света
//  внутри. Считается на каждый пиксель, слоёв под стеклом нет.
//
//  Вид снят по кадрам с записи экрана пользователя от 06.10.2026: одна лента,
//  у которой один край — яркая бирюзовая нить, другой — мягкий зелёный; концы
//  сходятся к средней линии и у торцов загибаются вдоль стекла.
//
//  Приём стекла — из ShaderKit (MIT, © 2025 James Rochabrun,
//  github.com/jamesrochabrun/ShaderKit, GlassShaders.metal, `glassRefraction`):
//  поле расстояний до кромки, смещение точки выборки по нормали, свет по
//  кромке. Текст лицензии — docs/licenses/ShaderKit-MIT.txt. Лента — своя.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Свет одной ленты в точке `u` (x и y от −1 до 1 внутри пилюли).
/// `edge` — яркая нить, `soft` — мягкий край; между ними заливка.
/// `blur` — во сколько раз размыть: 1 — сама лента, больше — её отражение.
static float3 ribbon(float2 u, float edge, float soft, float3 fillColor, float3 lineColor,
                     float lineGain, float blur) {
    float thickness = edge - soft;
    float width = max(abs(thickness), 0.004);
    // 0 на мягком краю, 1 на нити.
    float inside = (u.y - soft) / (thickness < 0.0 ? -width : width);
    float fill = smoothstep(-0.25 * blur, 0.9, inside)
               * (1.0 - smoothstep(1.0, 1.0 + 0.07 * blur / width, inside));
    // Тонкая лента светит слабее: в месте скрутки заливка сходит на нет.
    fill *= smoothstep(0.0, 0.16, width) * mix(0.55, 1.0, clamp(inside, 0.0, 1.0));

    float d = abs(u.y - edge);
    float line = exp(-pow(d / (0.042 * blur), 2.0)) + 0.6 * exp(-pow(d / (0.19 * blur), 2.0));
    float core = exp(-pow(d / (0.014 * blur), 2.0));

    return fillColor * fill + (lineColor * line * 0.75 + float3(1.0) * core * 0.08) * lineGain;
}

/// Обе ленты и их отсвет в точке `u`.
static float3 ribbons(float2 u, float time, float level, float blur) {
    // Лента гаснет к торцам: концы сходятся к средней линии.
    float envelope = pow(max(0.0, 1.0 - u.x * u.x), 2.0);
    float amplitude = 0.10 + 0.40 * level;

    // Скрученная лента: середина плавает, полуширина меняет знак вдоль x —
    // в этом месте края меняются местами.
    float center = envelope * amplitude * 0.30 * sin(1.2 * u.x + 0.9 * time);
    float half1 = envelope * amplitude * 0.95 * sin(0.9 * u.x - 1.3 * time + 0.6 * sin(0.37 * time));
    float3 light = ribbon(u, center + half1, center - half1,
                          float3(0.14, 0.90, 0.30), float3(0.36, 1.0, 0.88),
                          0.35 + 0.65 * sqrt(envelope), blur);

    // Вторая лента — тише и бледнее, в противоход.
    float center2 = envelope * amplitude * 0.22 * sin(2.3 * u.x - 0.7 * time + 1.9);
    float half2 = envelope * amplitude * 0.55 * sin(1.9 * u.x + 1.1 * time + 2.4);
    light += 0.42 * ribbon(u, center2 + half2, center2 - half2,
                           float3(0.10, 0.62, 0.34), float3(0.72, 0.92, 0.82), 0.3, blur);

    // Отсвет ленты на стекле вокруг неё.
    float ambient = exp(-pow(u.y / (0.6 * blur), 2.0)) * envelope * (0.08 + 0.22 * level);
    return light + float3(0.10, 0.50, 0.32) * ambient;
}

/// - Parameter size: размер кадра, pt.
/// - Parameter axes: полуоси пилюли, pt.
/// - Parameter exponent: показатель суперэллипса.
/// - Parameter time: секунды; период часа достаточно.
/// - Parameter level: громкость 0…1 (уже с дыханием в тишине).
[[ stitchable ]] half4 cloudOrb(float2 position, half4 current, float2 size,
                                float2 axes, float exponent, float time, float level) {
    float2 p = position - size * 0.5;
    float2 q = abs(p / axes);

    // 0 в центре, 1 на кромке пилюли.
    float radius = pow(pow(q.x, exponent) + pow(q.y, exponent), 1.0 / exponent);
    if (radius >= 1.0) {
        return half4(0.0h);
    }

    // Нормаль к кромке.
    float2 gradient = sign(p) * pow(q, float2(exponent - 1.0)) / axes;
    float2 normal = gradient / max(length(gradient), 1e-5);

    // Стекло: у кромки точка выборки уходит внутрь по нормали. У торцов
    // сильнее — там средняя линия загибается вдоль стекла; сверху и снизу
    // слабо, иначе свет ленты поднимался бы на всю кромку.
    float rim = smoothstep(0.84, 1.0, radius);
    float bend = rim * rim * axes.y * 0.5 * mix(0.15, 1.0, normal.x * normal.x);
    float2 u = (p - normal * bend) / axes;

    float3 light = ribbons(u, time, level, 1.0);

    // Отражения на внутренней стороне стекла: лента видна ещё раз у дна и
    // слабее у верха — перевёрнутая, сжатая и размытая.
    float2 below = float2(u.x * 0.9, (0.74 - u.y) * 2.4);
    float2 above = float2(u.x * 0.9, (-0.78 - u.y) * 2.8);
    float3 mirror = ribbons(below, time, level, 3.2) * smoothstep(0.30, 0.74, u.y) * 0.34
                  + ribbons(above, time, level, 3.6) * smoothstep(-0.36, -0.78, u.y) * 0.16;
    light += mirror * (1.0 - rim);

    // Тело: почти чёрное сверху, чуть светлее и серее к низу.
    float3 body = mix(float3(0.010, 0.035, 0.028), float3(0.050, 0.085, 0.080),
                      smoothstep(-1.0, 1.0, p.y / axes.y));

    float3 color = body + light;

    // Мягкий блик неба на верхней части стекла.
    float sheen = exp(-pow((u.y + 0.62) / 0.22, 2.0)) * pow(max(0.0, 1.0 - u.x * u.x), 1.5);
    color += float3(0.55, 0.80, 0.72) * sheen * 0.045;

    // Толщина стекла: полоса тени перед кромкой.
    float shade = smoothstep(0.62, 0.90, radius) * (1.0 - smoothstep(0.90, 1.0, radius));
    color *= 1.0 - 0.35 * shade;

    // Кромка: едва заметная нить, ярче к низу, и свет ленты, собранный стеклом.
    float edge = smoothstep(0.965, 1.0, radius);
    color += float3(0.45, 0.80, 0.70) * edge * (0.07 + 0.16 * smoothstep(-0.2, 1.0, normal.y));
    color += light * rim * 0.55;

    float alpha = 1.0 - smoothstep(1.0 - 1.5 / min(axes.x, axes.y), 1.0, radius);
    return half4(half3(color), 1.0h) * half(alpha);
}
