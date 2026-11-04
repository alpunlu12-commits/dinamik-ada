using System;

namespace DinamikAda.UI;

/// <summary>
/// SwiftUI'daki .spring(response:dampingFraction:) karşılığı: tek bir değeri
/// hedefine sönümlü yayla götürür. response bir salınımın süresi (sn),
/// damping 1'in altında hafif aşma verir.
/// </summary>
public sealed class Spring
{
    public double Value { get; private set; }
    public double Target { get; private set; }
    private double _velocity;

    public Spring(double initial) { Value = Target = initial; }

    public bool IsSettled => Math.Abs(Value - Target) < 0.01 && Math.Abs(_velocity) < 0.05;

    public void SetTarget(double target) => Target = target;

    /// <summary>Animasyonsuz atla (ilk kurulum, ekran değişimi).</summary>
    public void Snap(double value) { Value = Target = value; _velocity = 0; }

    public void Step(double dt, double response, double damping)
    {
        if (IsSettled) { Value = Target; _velocity = 0; return; }
        var omega = 2 * Math.PI / Math.Max(0.05, response);
        // Kararlılık için küçük alt adımlar.
        var steps = Math.Max(1, (int)Math.Ceiling(dt / (1.0 / 240)));
        var h = dt / steps;
        for (var i = 0; i < steps; i++)
        {
            var accel = -omega * omega * (Value - Target) - 2 * damping * omega * _velocity;
            _velocity += accel * h;
            Value += _velocity * h;
        }
    }
}
