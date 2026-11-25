import Foundation

/// One eyeball of the angry face, in the 1080x420 "eye space" of the reference clip
/// (the 1080-wide strip of `Vedio/angry eyes.mp4` at y 900...1320; the eyes sit at x 122...957).
///
/// The eyeball is a circle with a soft radial shade towards its rim, cut by an angled upper lid
/// (`y = lidY0 + lidSlope*u + lidK*u^2 + lidQ*u^3`, `u = (x - cx) / radius`) and, while the eyes
/// shut, by a rising lower lid. A black pupil with a small highlight sits on the ball.
/// Every value was fitted frame by frame to the clip.
public struct AngryEyeGeometry: Equatable, Sendable {
    public var cx: Double
    public var cy: Double
    public var radius: Double
    public var lidY0: Double
    public var lidSlope: Double
    public var lidK: Double
    public var lidQ: Double
    /// Scale of the soft shadow under the upper lid (1 = same falloff as the rim).
    public var lidShade: Double
    /// Softness of the upper lid edge in px (the lids are blurry while the eyes open and close).
    public var lidSoft: Double
    public var lowerY0: Double
    public var lowerSlope: Double
    public var lowerSoft: Double
    /// Edge softness in px (about 2 when sharp; the fade in/out is blurrier).
    public var blur: Double
    /// Global brightness 0...1 (the fade in and out).
    public var brightness: Double
    public var pupilX: Double
    public var pupilY: Double
    public var pupilRadius: Double
    /// Highlight offset from the pupil centre.
    public var highlightX: Double
    public var highlightY: Double
    public var highlightRadius: Double

    public var pupilOffsetX: Double { pupilX - cx }
    public var pupilOffsetY: Double { pupilY - cy }

    /// y of the upper lid line at normalised x `u`.
    public func lidY(atU u: Double) -> Double {
        lidY0 + lidSlope * u + lidK * u * u + lidQ * u * u * u
    }

    /// Element-wise blend (`k` 0 = self, 1 = other).
    public func blended(to o: AngryEyeGeometry, _ k: Double) -> AngryEyeGeometry {
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * k }
        return AngryEyeGeometry(
            cx: m(cx, o.cx), cy: m(cy, o.cy), radius: m(radius, o.radius),
            lidY0: m(lidY0, o.lidY0), lidSlope: m(lidSlope, o.lidSlope),
            lidK: m(lidK, o.lidK), lidQ: m(lidQ, o.lidQ), lidShade: m(lidShade, o.lidShade),
            lidSoft: m(lidSoft, o.lidSoft),
            lowerY0: m(lowerY0, o.lowerY0), lowerSlope: m(lowerSlope, o.lowerSlope),
            lowerSoft: m(lowerSoft, o.lowerSoft), blur: m(blur, o.blur),
            brightness: m(brightness, o.brightness),
            pupilX: m(pupilX, o.pupilX), pupilY: m(pupilY, o.pupilY),
            pupilRadius: m(pupilRadius, o.pupilRadius),
            highlightX: m(highlightX, o.highlightX), highlightY: m(highlightY, o.highlightY),
            highlightRadius: m(highlightRadius, o.highlightRadius))
    }
}

/// Everything the angry face needs to draw one frame.
public struct AngryEyesPose: Equatable, Sendable {
    public var left: AngryEyeGeometry
    public var right: AngryEyeGeometry
    /// Fractional 1-based frame of the source clip (0 when synthesised by the choreography).
    public var frame: Double = 0
    /// 1 = lids as measured, 0 = shut (set by the choreography; the clip itself never shuts them).
    public var openness: Double = 1
    /// Lid state relative to the open state the iris is fitted to (1 = open, less = the lids are
    /// closing or opening over it). Set by the choreography; the renderer does not read it.
    public var lidOpen: Double = 1

    public var isDark: Bool { left.brightness < 0.01 && right.brightness < 0.01 }

    public func blended(to o: AngryEyesPose, _ k: Double) -> AngryEyesPose {
        AngryEyesPose(left: left.blended(to: o.left, k), right: right.blended(to: o.right, k),
                      frame: k < 0.5 ? frame : o.frame,
                      openness: openness + (o.openness - openness) * k,
                      lidOpen: lidOpen + (o.lidOpen - lidOpen) * k)
    }
}

/// The measured look of `Vedio/angry eyes.mp4` (540 frames @ 60 fps, 9 s): eyes fade in from the
/// lower crescent, look around under the angled lid, then dim and shut with a rising lower lid.
public enum AngryEyesTimeline {
    public static let fps: Double = 60
    public static let frameCount = 540
    public static let duration: TimeInterval = Double(frameCount) / fps
    /// Size of the eye space the geometry lives in.
    public static let spaceWidth: Double = 1080
    public static let spaceHeight: Double = 420

    /// Pose at `t` seconds; clamped to the clip.
    public static func pose(at t: TimeInterval) -> AngryEyesPose {
        let fp = min(Double(frameCount), max(1, t * fps + 1))   // 1-based
        func eye(_ base: Int) -> AngryEyeGeometry {
            func v(_ c: Int) -> Double { keyed(tracks[base + c], fp) }
            return AngryEyeGeometry(
                cx: v(0), cy: v(1), radius: v(2), lidY0: v(3), lidSlope: v(4), lidK: v(5), lidQ: v(6),
                lidShade: v(7), lidSoft: v(19), lowerY0: v(16), lowerSlope: v(17), lowerSoft: v(18), blur: v(8),
                brightness: v(9), pupilX: v(10), pupilY: v(11), pupilRadius: v(14),
                highlightX: v(12), highlightY: v(13), highlightRadius: v(15))
        }
        var p = AngryEyesPose(left: eye(0), right: eye(20))
        p.frame = fp
        return p
    }

    // MARK: Interpolation

    private static func keyed(_ keys: [(Double, Double)], _ fp: Double) -> Double {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if fp <= first.0 { return first.1 }
        if fp >= last.0 { return last.1 }
        for i in 1..<keys.count where fp <= keys[i].0 {
            let (f0, v0) = keys[i - 1], (f1, v1) = keys[i]
            return v0 + (v1 - v0) * (fp - f0) / (f1 - f0)
        }
        return last.1
    }

    // MARK: Measured tracks

    /// Per eye (left, then right) 20 channels, each a piecewise-linear "frame:value" key list,
    /// simplified from the per-frame fit within sub-pixel tolerance. Channel order:
    /// cx cy radius lidY0 lidSlope lidK lidQ lidShade blur brightness pupilX pupilY
    /// highlightX highlightY pupilRadius highlightRadius lowerY0 lowerSlope lowerSoft lidSoft.
    private static let tracks: [[(Double, Double)]] = trackText.map { text in
        text.split(separator: " ").map { pair in
            let p = pair.split(separator: ":")
            return (Double(p[0]) ?? 0, Double(p[1]) ?? 0)
        }
    }

    private static let trackText: [String] = [
        "1:308.6 28:308.6 30:311.6 40:316.1 50:315.8 111:303.2 131:300.3 150:299.1 172:303.5 199:313.0 219:318.8 233:321.0 248:321.2 283:319.1 400:304.8 423:303.5 491:303.3 496:302.0 499:299.7 501:295.4 504:286.2 505:282.3 506:276.6 507:269.1 509:250.7 510:243.2 511:238.5 512:236.3 540:236.3",
        "1:166.7 28:166.7 36:164.2 41:160.8 50:158.1 56:158.4 97:152.6 135:149.7 158:150.6 180:153.8 184:153.5 227:160.5 252:160.9 290:160.0 391:152.9 490:152.0 495:153.9 496:153.5 499:149.4 500:145.6 503:124.3 505:113.1 506:108.3 507:106.5 510:104.9 512:102.7 540:102.7",
        "1:163.6 28:163.6 36:168.7 40:172.4 50:176.5 112:187.2 134:189.4 158:188.6 185:183.3 227:173.1 243:172.5 290:174.2 391:184.7 414:185.8 490:186.2 505:182.6 506:180.1 507:174.8 509:160.1 510:154.4 511:151.3 512:150.2 540:150.2",
        "1:305.8 28:305.8 34:277.4 37:261.2 42:232.4 53:164.5 60:127.0 64:110.6 68:97.9 72:89.9 76:86.4 89:91.6 127:117.3 140:123.2 168:128.2 209:123.7 227:124.2 239:127.2 264:142.6 279:147.4 291:146.0 310:139.3 357:113.5 370:108.3 382:105.4 395:107.2 403:110.8 439:133.1 447:135.5 465:136.0 471:137.6 478:149.1 482:158.1 492:184.9 500:209.4 505:221.8 507:223.2 510:222.9 512:227.8 540:227.8",
        "1:72.9 28:72.9 35:67.4 48:74.4 71:78.4 470:76.0 493:78.5 506:90.2 512:76.1 540:76.1",
        "1:-6.2 28:-6.2 29:-11.7 32:-5.1 42:-7.0 62:3.3 106:-4.2 220:1.7 493:1.5 499:-7.3 506:-37.7 512:-47.7 540:-47.7",
        "1:-23.7 29:-24.1 32:-6.2 36:-2.1 71:-6.8 113:8.2 163:7.0 238:-5.2 470:5.5 494:-1.0 500:-21.7 506:-70.8 509:-85.6 540:-86.2",
        "1:1.774 28:1.774 30:1.659 41:1.313 51:1.273 62:1.428 64:1.389 71:1.043 75:0.913 95:0.868 157:0.866 243:0.953 468:0.879 472:0.920 478:1.103 485:1.394 490:1.492 494:1.469 499:1.370 504:1.162 506:1.030 510:0.570 512:0.407 540:0.407",
        "1:9.6 28:9.6 29:8.7 30:8.5 34:9.5 40:7.0 43:4.0 46:2.8 62:2.2 212:2.3 254:2.0 392:2.3 490:2.0 499:2.2 506:3.0 507:3.7 508:5.3 510:10.5 511:12.7 512:13.8 540:13.8",
        "1:0.000 21:0.000 24:0.075 26:0.231 28:0.269 34:0.527 35:0.541 37:0.621 61:1.019 144:1.004 211:1.033 441:1.009 477:0.759 509:0.466 511:0.418 521:0.000 540:0.000",
        "1:323.0 40:323.0 56:318.9 64:314.9 74:306.7 86:293.6 115:255.8 125:244.1 137:234.1 146:230.9 159:235.6 165:240.4 172:247.7 185:264.5 226:324.1 237:338.3 245:347.3 255:356.8 263:362.8 271:367.3 278:369.2 300:368.9 304:367.9 358:344.5 400:322.8 414:317.6 426:314.6 450:311.1 487:308.6 507:310.5 509:312.0 512:316.4 540:316.4",
        "1:153.9 85:154.9 117:151.6 136:151.6 183:153.5 232:160.7 258:160.8 282:157.9 294:157.8 334:161.9 375:158.4 411:157.3 447:151.6 508:151.8 512:153.9 540:153.9",
        "1:-75.7 40:-75.7 41:-72.2 42:-71.9 44:-59.6 48:-50.6 49:-49.9 149:-53.2 269:-48.2 403:-52.2 480:-52.0 492:-52.9 495:-54.7 497:-52.2 499:-43.1 501:-39.9 540:-39.9",
        "1:32.2 40:32.2 41:23.4 46:1.0 51:-5.0 53:-5.5 158:-6.5 226:-5.1 268:-6.8 488:-5.4 493:-6.0 494:-7.4 496:-14.9 497:-16.2 500:-13.7 540:-13.7",
        "1:88.4 60:89.0 136:94.6 165:93.6 230:86.5 259:85.7 402:92.6 495:93.1 540:92.1",
        "1:19.5 40:19.5 45:14.0 48:13.6 52:16.7 118:17.8 222:16.3 417:17.6 493:16.9 494:17.3 497:25.0 498:25.8 540:25.9",
        "1:900.0 437:900.0 438:865.0 439:725.0 440:515.1 441:375.1 442:340.1 465:340.7 470:337.8 499:262.8 512:236.6 540:236.6",
        "1:60.0 437:60.0 438:58.3 441:34.8 442:33.0 465:36.0 495:32.4 504:35.9 511:27.8 540:27.7",
        "1:3.0 437:3.0 438:5.3 439:14.6 440:28.4 441:37.7 442:40.0 504:40.0 511:34.9 540:34.8",
        "1:27.8 28:27.8 38:39.8 43:35.6 53:36.8 59:33.0 63:37.5 66:38.2 68:35.7 70:29.6 76:4.8 80:2.0 453:1.2 470:3.6 471:6.0 477:32.5 480:39.6 482:41.1 489:39.3 495:33.8 500:36.0 507:29.5 511:35.3 512:39.3 540:39.3",
        "1:768.0 28:768.0 34:765.9 47:764.2 113:777.3 149:780.9 171:776.9 216:762.0 233:759.0 247:758.7 310:763.6 379:773.2 403:775.6 427:776.7 496:777.2 499:779.3 501:781.9 503:786.5 506:797.0 507:801.6 508:807.7 509:815.5 511:833.6 512:840.3 540:840.3",
        "1:165.3 37:164.5 48:159.2 96:152.9 131:149.9 162:151.1 171:152.8 188:154.0 218:159.3 254:161.0 276:160.6 399:152.8 495:152.5 499:154.4 501:152.6 503:147.6 504:142.2 505:135.3 508:110.8 509:107.1 511:105.9 512:104.2 540:104.2",
        "1:165.8 28:165.8 37:168.6 48:175.5 96:184.6 131:189.3 161:188.1 188:182.6 218:174.8 236:172.7 254:172.3 276:173.1 399:185.1 495:185.9 498:184.4 501:181.3 504:176.7 507:175.0 508:173.5 509:168.8 511:155.6 512:151.7 540:151.7",
        "1:305.3 28:305.3 31:291.2 35:269.7 42:227.3 51:168.2 58:127.9 63:105.3 66:95.6 70:86.6 73:84.5 89:91.4 123:113.4 139:121.2 167:126.5 202:123.2 233:124.9 240:127.5 269:145.6 279:147.9 289:147.1 307:141.8 371:108.7 384:105.8 393:107.3 403:111.3 429:128.5 440:134.0 450:136.4 475:137.6 480:145.2 485:156.0 496:187.7 503:210.5 506:217.3 512:222.4 540:222.4",
        "1:-67.2 35:-67.6 50:-76.5 62:-74.7 97:-80.6 168:-78.2 174:-72.2 328:-72.2 367:-77.0 478:-77.0 491:-78.6 500:-86.0 509:-87.7 540:-85.8",
        "1:-17.6 28:-17.6 33:-4.1 36:-10.1 63:2.2 330:-3.9 493:0.8 499:-4.8 510:-39.3 540:-39.2",
        "1:23.5 28:23.5 33:2.1 39:-1.6 50:4.2 59:-1.9 97:4.2 169:-1.9 174:-11.2 238:-2.5 326:-7.7 362:-6.6 367:-1.4 475:-4.0 491:-1.1 497:7.4 505:40.5 510:80.6 512:91.0 540:91.0",
        "1:1.743 28:1.743 30:1.630 38:1.338 44:1.270 50:1.279 61:1.403 69:1.001 73:0.904 130:0.862 253:0.941 469:0.874 476:0.917 480:1.042 490:1.462 494:1.518 497:1.430 500:1.401 505:1.233 509:0.933 512:0.441 540:0.441",
        "1:9.0 28:9.0 29:8.7 34:9.5 38:8.4 40:7.0 43:4.3 46:2.8 66:2.1 180:2.4 253:2.0 492:2.0 503:2.3 507:2.9 509:4.4 510:6.2 512:11.0 540:11.0",
        "1:0.000 21:0.000 23:0.057 24:0.170 25:0.223 29:0.346 30:0.410 35:0.593 42:0.724 61:1.015 167:1.005 257:1.044 441:1.010 470:0.813 489:0.659 503:0.516 512:0.482 514:0.412 521:0.000 540:0.000",
        "1:754.1 40:754.1 56:756.9 68:754.8 78:749.8 88:742.8 117:715.8 128:706.9 137:701.6 146:699.5 159:701.8 165:704.1 193:721.4 212:737.3 252:780.0 267:792.7 278:798.1 300:802.1 366:791.1 405:778.7 438:772.2 478:768.3 508:769.6 511:768.5 512:766.4 540:766.4",
        "1:153.5 82:155.0 109:151.8 125:151.7 179:155.1 192:154.4 231:160.5 252:160.8 298:157.5 325:160.9 342:161.3 371:158.4 411:157.1 450:151.5 489:152.4 510:151.3 512:152.8 540:152.8",
        "1:80.4 41:80.5 44:60.9 47:52.4 49:50.5 55:49.8 137:53.0 250:48.5 405:52.3 494:52.8 498:50.6 504:54.3 540:54.3",
        "1:32.9 40:32.9 41:18.7 42:8.4 44:-1.5 46:-4.6 54:-5.8 109:-5.4 164:-8.0 211:-5.0 466:-6.5 496:-5.9 502:-2.6 540:-2.6",
        "1:88.7 54:88.6 109:93.7 137:94.1 180:90.3 192:90.7 223:87.0 268:86.2 402:92.7 540:93.4",
        "1:14.6 40:14.6 41:18.8 42:21.3 43:20.8 46:16.1 48:15.3 52:16.7 133:18.1 236:16.2 467:17.7 490:17.5 503:14.4 540:14.4",
        "1:900.0 437:900.0 438:865.0 439:725.2 440:515.5 441:375.7 442:340.7 464:341.2 470:338.5 500:259.8 512:235.8 540:235.8",
        "1:-60.0 437:-60.0 438:-58.2 441:-33.1 443:-30.6 540:-27.6",
        "1:3.0 437:3.0 438:5.3 439:14.6 440:28.4 441:37.7 442:40.0 507:40.0 512:35.7 540:35.7",
        "1:30.1 28:30.1 32:37.3 37:38.4 40:35.6 44:37.9 50:37.4 59:33.5 63:39.0 67:30.7 72:4.9 76:1.8 472:1.2 475:4.1 481:33.3 485:41.8 492:38.9 496:34.7 501:36.6 505:32.0 508:31.4 510:32.1 512:37.0 540:37.0"
    ]
}
