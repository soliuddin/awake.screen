# Stay Awake: a frameless floating button for Windows (no install needed).
# ON  = glossy colour-cycling button with tick ring, comets, beads, ripples and sparks. Screen stays awake.
# OFF = red button. Windows may sleep normally again.
#   Left click   turn on / off
#   Drag         move the button
#   Right click  quit
# No network access, nothing written to disk.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace Win -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);'

$ES_AWAKE = [uint32]2147483651   # ES_CONTINUOUS + ES_SYSTEM_REQUIRED + ES_DISPLAY_REQUIRED
$ES_NORMAL = [uint32]2147483648  # ES_CONTINUOUS only: lets Windows sleep again

$SIZE = 150                      # window size in pixels; everything below scales from $R
$C = $SIZE / 2
$R = $SIZE * 0.22                # button radius
$TAU = [math]::PI * 2
$NT = 48                         # ticks in the ring

$st = @{ on = $true; t = 0.0; hue = (28 / 360); last = 0.0; rippleClock = 0.0; sparkAcc = 0.0; down = $null; start = $null; moved = $false }
$st.sparks = New-Object System.Collections.ArrayList
$st.ripples = New-Object System.Collections.ArrayList
$rng = New-Object System.Random
$sw = [System.Diagnostics.Stopwatch]::StartNew()

# ---------- colour helpers ----------

function Hue2Rgb($p, $q, $tc) {
    if ($tc -lt 0) { $tc += 1 }
    if ($tc -gt 1) { $tc -= 1 }
    if ($tc -lt (1 / 6)) { return $p + ($q - $p) * 6 * $tc }
    if ($tc -lt 0.5) { return $q }
    if ($tc -lt (2 / 3)) { return $p + ($q - $p) * (2 / 3 - $tc) * 6 }
    return $p
}

# fully saturated colour from hue in degrees and lightness 0..1
function HslColor($deg, $lv) {
    $h = $deg / 360
    if ($lv -lt 0.5) { $q = 2 * $lv } else { $q = 1 }
    $p = 2 * $lv - $q
    $r = Hue2Rgb $p $q ($h + 1 / 3)
    $g = Hue2Rgb $p $q $h
    $b = Hue2Rgb $p $q ($h - 1 / 3)
    [System.Drawing.Color]::FromArgb([int]($r * 255), [int]($g * 255), [int]($b * 255))
}

# one 360-step colour table per lightness, so drawing never has to convert colours
$PAL = @{}
foreach ($lv in 9, 50, 55, 62, 66, 70, 85) {
    $arr = New-Object 'System.Drawing.Color[]' 360
    for ($i = 0; $i -lt 360; $i++) { $arr[$i] = HslColor $i ($lv / 100.0) }
    $PAL[$lv] = $arr
}
$P09 = $PAL[9]; $P50 = $PAL[50]; $P55 = $PAL[55]; $P62 = $PAL[62]; $P66 = $PAL[66]; $P70 = $PAL[70]; $P85 = $PAL[85]

function Hi($deg) { [int][math]::Floor((($deg % 360) + 360) % 360) }

function Fx($a, $col) {
    $v = [int][math]::Max(0, [math]::Min(255, $a))
    [System.Drawing.Color]::FromArgb($v, $col)
}

function Rnd($a, $b) { $a + $rng.NextDouble() * ($b - $a) }

# ---------- drawing helpers (one shared pen and brush) ----------

$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [single]1)
$pen.StartCap = 'Round'
$pen.EndCap = 'Round'
$br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

function RingP($g, $color, $w, $r) {
    $pen.Color = $color
    $pen.Width = $w
    $g.DrawEllipse($pen, $C - $r, $C - $r, 2 * $r, 2 * $r)
}

function Dot($g, $color, $x, $y, $r) {
    $br.Color = $color
    $g.FillEllipse($br, $x - $r, $y - $r, 2 * $r, 2 * $r)
}

# a bright head with a tapering tail circling the button
function Comet($g, $r, $head, $dir, $dh, $w, $hd) {
    $n = 16
    $step = 0.10
    $stepDeg = $step * 180 / [math]::PI
    for ($k = 0; $k -lt $n; $k++) {
        $tt = 1.0 - $k / $n
        $a0 = $head - $dir * $k * $step
        if ($dir -gt 0) { $startDeg = ($a0 - $step * 1.3) * 180 / [math]::PI } else { $startDeg = $a0 * 180 / [math]::PI }
        $pen.Width = $SIZE * 0.015 * $w * (0.35 + 0.65 * $tt)
        $pen.Color = [System.Drawing.Color]::FromArgb([int]($tt * $tt * 242), $P62[(Hi ($hd + $dh + $k * 4))])
        $g.DrawArc($pen, $C - $r, $C - $r, 2 * $r, 2 * $r, $startDeg, $stepDeg * 1.3)
    }
    $hx = $C + [math]::Cos($head) * $r
    $hy = $C + [math]::Sin($head) * $r
    Dot $g (Fx 90 $P85[(Hi ($hd + $dh))]) $hx $hy ($SIZE * 0.028 * $w)
    Dot $g (Fx 255 $P85[(Hi ($hd + $dh))]) $hx $hy ($SIZE * 0.011 * $w)
}

function SetAwake($enable) {
    if ($enable) { [void][Win.Power]::SetThreadExecutionState($ES_AWAKE) }
    else { [void][Win.Power]::SetThreadExecutionState($ES_NORMAL) }
}

# ---------- light-show state ----------

function Spawn($speed) {
    if ($st.sparks.Count -gt 70) { return }
    $s = @{ a = (Rnd 0 $TAU); d = 1.04; v = (Rnd 0.3 0.7) * $speed; life = 0.0; max = (Rnd 0.9 1.9); s = (Rnd 0.008 0.016); dh = (Rnd (-50) 50) }
    [void]$st.sparks.Add($s)
}

function Burst($isOn) {
    if ($isOn) { $n = 40; $sp = 1.6 } else { $n = 16; $sp = 0.9 }
    for ($i = 0; $i -lt $n; $i++) { Spawn $sp }
    [void]$st.ripples.Add(@{ age = 0.0; fast = $true })
    if ($isOn) { [void]$st.ripples.Add(@{ age = -0.14; fast = $true }) }
}

function Update($dt) {
    $st.t += $dt
    if ($st.on) {
        $st.hue = ((28 / 360) + $st.t * 0.1) % 1       # a full colour cycle every 10 seconds
        $st.sparkAcc += $dt * 14
        while ($st.sparkAcc -ge 1) { $st.sparkAcc -= 1; Spawn 1.0 }
        $st.rippleClock += $dt
        if ($st.rippleClock -gt 0.95) { $st.rippleClock = 0.0; [void]$st.ripples.Add(@{ age = 0.0; fast = $false }) }
    }
    for ($i = $st.sparks.Count - 1; $i -ge 0; $i--) {
        $s = $st.sparks[$i]
        $s.life = $s.life + $dt
        if ($s.life -ge $s.max) { $st.sparks.RemoveAt($i); continue }
        $s.d = $s.d + $s.v * $dt
        $s.v = $s.v * [math]::Max(0, 1 - 0.8 * $dt)
        $s.a = $s.a + 0.35 * $dt
    }
    for ($i = $st.ripples.Count - 1; $i -ge 0; $i--) {
        $rp = $st.ripples[$i]
        $rp.age = $rp.age + $dt
        if ($rp.fast) { $dur = 0.9 } else { $dur = 2.4 }
        if ($rp.age -ge $dur) { $st.ripples.RemoveAt($i) }
    }
}

# precomputed tick positions
$tx1 = New-Object 'double[]' $NT; $ty1 = New-Object 'double[]' $NT
$tx2 = New-Object 'double[]' $NT; $ty2 = New-Object 'double[]' $NT
for ($i = 0; $i -lt $NT; $i++) {
    $a = $i * $TAU / $NT
    $tx1[$i] = $C + [math]::Cos($a) * $R * 1.4;  $ty1[$i] = $C + [math]::Sin($a) * $R * 1.4
    $tx2[$i] = $C + [math]::Cos($a) * $R * 1.52; $ty2[$i] = $C + [math]::Sin($a) * $R * 1.52
}

# ---------- window ----------

$key = [System.Drawing.Color]::FromArgb(1, 2, 3)   # this colour is see-through, so only the button shows
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Stay Awake'
$form.FormBorderStyle = 'None'
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.StartPosition = 'Manual'
$form.ClientSize = New-Object System.Drawing.Size($SIZE, $SIZE)
$form.BackColor = $key
$form.TransparencyKey = $key
$form.Cursor = [System.Windows.Forms.Cursors]::Hand
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($wa.Right - $SIZE - 30), ($wa.Bottom - $SIZE - 30))
$form.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic').SetValue($form, $true, $null)

$form.add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $t = $st.t
    if ($st.on) { $hd = $st.hue * 360 } else { $hd = 0 }   # off = red

    if ($st.on) {
        # breathing glow: thin rings
        $pulse = [math]::Sin($t * 2.1)
        for ($k = 0; $k -lt 4; $k++) {
            RingP $g (Fx (70 - $k * 15 + $pulse * 12) $P55[(Hi ($hd + 180))]) 3 ($R * (1.15 + $k * 0.1 + $pulse * 0.04))
        }

        # radar sweep over the ring of ticks
        $sweep = $t * 2.4
        $pen.Width = 1.7
        for ($i = 0; $i -lt $NT; $i++) {
            $a = $i * $TAU / $NT
            $d = ((($sweep - $a) % $TAU) + $TAU) % $TAU
            $al = 0.14 + 0.86 * [math]::Pow(1 - $d / $TAU, 3)
            $pen.Color = [System.Drawing.Color]::FromArgb([int]($al * 255), $P62[[int][math]::Floor((($hd + $i * 7.5) % 360 + 360) % 360)])
            $g.DrawLine($pen, $tx1[$i], $ty1[$i], $tx2[$i], $ty2[$i])
        }
    } else {
        # idle: dim red glow, ring of ticks and two thin orbits
        $red = [System.Drawing.Color]::FromArgb(255, 60, 70)
        for ($k = 0; $k -lt 4; $k++) { RingP $g (Fx (50 - $k * 11) $red) 3 ($R * (1.15 + $k * 0.1)) }
        $pen.Width = 1.7
        $pen.Color = Fx 80 $red
        for ($i = 0; $i -lt $NT; $i++) { $g.DrawLine($pen, $tx1[$i], $ty1[$i], $tx2[$i], $ty2[$i]) }
        RingP $g (Fx 70 $red) 1.4 ($R * 1.24)
        RingP $g (Fx 45 $red) 1.4 ($R * 1.68)
    }

    # ripples leave the button and thin out as they travel
    foreach ($rp in $st.ripples) {
        if ($rp.age -lt 0) { continue }
        if ($rp.fast) { $prog = $rp.age / 0.9; $span = 1.2; $rw = $SIZE * 0.014; $rpal = $P85 } else { $prog = $rp.age / 2.4; $span = 1.15; $rw = $SIZE * 0.009; $rpal = $P62 }
        RingP $g (Fx ([math]::Pow(1 - $prog, 1.5) * 217) $rpal[(Hi ($hd + $prog * 80))]) ($rw * (1 - $prog * 0.5)) ($R * (1.03 + $prog * $span))
    }

    if ($st.on) {
        # three comets: two turn one way, one the other
        Comet $g ($R * 1.24) ($t * 1.7) 1 0 1.5 $hd
        Comet $g ($R * 1.68) (-$t * 1.15 + 2) -1 120 1.2 $hd
        Comet $g ($R * 1.9) ($t * 0.8 + 4) 1 220 1.0 $hd

        # eight rainbow beads on the outer orbit
        for ($i = 0; $i -lt 8; $i++) {
            $a = $t * 0.9 + $i * $TAU / 8
            $bx = $C + [math]::Cos($a) * $R * 2.08
            $by = $C + [math]::Sin($a) * $R * 2.08
            $bc = $P70[(Hi ($hd + $i * 45))]
            Dot $g (Fx 80 $bc) $bx $by ($SIZE * 0.028)
            Dot $g (Fx 235 $bc) $bx $by ($SIZE * 0.012)
        }
    }

    # sparks
    foreach ($s in $st.sparks) {
        $tt = $s.life / $s.max
        $sx = $C + [math]::Cos($s.a) * $s.d * $R
        $sy = $C + [math]::Sin($s.a) * $s.d * $R
        Dot $g (Fx ([math]::Pow(1 - $tt, 1.4) * 255) $P70[(Hi ($hd + $s.dh))]) $sx $sy ($SIZE * $s.s * (1 - $tt * 0.4))
    }

    # the button
    $rect = New-Object System.Drawing.RectangleF(($C - $R), ($C - $R), (2 * $R), (2 * $R))
    if ($st.on) {
        $top = $P66[(Hi $hd)]
        $bottom = $P55[(Hi ($hd + 35))]
        $iconColor = $P09[(Hi $hd)]
    } else {
        $top = [System.Drawing.Color]::FromArgb(255, 92, 92)
        $bottom = [System.Drawing.Color]::FromArgb(196, 26, 44)
        $iconColor = [System.Drawing.Color]::FromArgb(70, 8, 16)
    }
    $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $top, $bottom, [single]90)
    $g.FillEllipse($gb, $C - $R, $C - $R, 2 * $R, 2 * $R)
    $gb.Dispose()

    # rim: a turning rainbow while on, solid red while off
    $rr = $R * 1.06
    $pen.Width = 3
    if ($st.on) {
        for ($i = 0; $i -lt 12; $i++) {
            $pen.Color = $P66[(Hi ($hd + $i * 30))]
            $g.DrawArc($pen, $C - $rr, $C - $rr, 2 * $rr, 2 * $rr, ($t * 60 + $i * 30), 31)
        }
        RingP $g (Fx 200 $P62[(Hi $hd)]) 1.6 ($R * 1.13)
    } else {
        RingP $g ([System.Drawing.Color]::FromArgb(255, 80, 90)) 3 $rr
        RingP $g (Fx 200 ([System.Drawing.Color]::FromArgb(255, 120, 120))) 1.6 ($R * 1.13)
    }

    # power icon
    $pen.Color = $iconColor
    $pen.Width = $R * 0.13
    $ir = $R * 0.44
    $g.DrawArc($pen, $C - $ir, $C - $ir + $R * 0.06, 2 * $ir, 2 * $ir, 300, 300)
    $g.DrawLine($pen, $C, $C - $R * 0.5, $C, $C - $R * 0.06)
})

$form.add_MouseDown({
    param($sender, $e)
    $st.down = [System.Windows.Forms.Control]::MousePosition
    $st.start = $form.Location
    $st.moved = $false
})

$form.add_MouseMove({
    param($sender, $e)
    if ($e.Button -eq 'Left' -and $st.down -ne $null) {
        $p = [System.Windows.Forms.Control]::MousePosition
        $dx = $p.X - $st.down.X
        $dy = $p.Y - $st.down.Y
        if ([math]::Abs($dx) + [math]::Abs($dy) -gt 4) { $st.moved = $true }
        if ($st.moved) {
            $form.Location = New-Object System.Drawing.Point(($st.start.X + $dx), ($st.start.Y + $dy))
        }
    }
})

$form.add_MouseUp({
    param($sender, $e)
    if ($e.Button -eq 'Right') {
        SetAwake $false
        $form.Close()
    } elseif ($e.Button -eq 'Left' -and -not $st.moved) {
        $st.on = -not $st.on
        Burst $st.on
        SetAwake $st.on
        $form.Invalidate()
    }
})

$form.add_FormClosing({ SetAwake $false })

# animation runs only while the button is on or a burst is still fading; the red idle button costs nothing
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 33
$timer.add_Tick({
    $now = $sw.Elapsed.TotalSeconds
    $dt = [math]::Min(0.05, $now - $st.last)
    $st.last = $now
    if ($st.on -or $st.sparks.Count -gt 0 -or $st.ripples.Count -gt 0) {
        Update $dt
        $form.Invalidate()
    }
})

[System.Windows.Forms.Application]::EnableVisualStyles()
SetAwake $true
$timer.Start()
[System.Windows.Forms.Application]::Run($form)
