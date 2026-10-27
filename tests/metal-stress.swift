// macOS counterpart of gles-stress.c: the same per-pixel xorshift math
// (1024x1024, 400 iterations, new seed per frame), run as a Metal compute
// kernel. Every 10th frame is read back and checked against the CPU.
// Run: swift -O metal-stress.swift <seconds>
// METAL_STRESS_CHECK_EVERY=n waits and checks every n-th frame (default 10; 0 never waits),
// the same option as VK_STRESS_CHECK_EVERY in vk-stress.c.
import Foundation
import Metal

let W = 1024, H = 1024, ITERS = 400
let seconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 60 : 60
let checkEvery = Int(ProcessInfo.processInfo.environment["METAL_STRESS_CHECK_EVERY"] ?? "") ?? 10

let src = """
#include <metal_stdlib>
using namespace metal;
kernel void k(device uint *o [[buffer(0)]], constant uint &seed [[buffer(1)]],
              uint2 g [[thread_position_in_grid]]) {
    uint s = (g.x * 73856093u) ^ (g.y * 19349663u) ^ seed;
    for (int i = 0; i < \(ITERS); i++) { s ^= s << 13; s ^= s >> 17; s ^= s << 5; s += uint(i); }
    o[g.y * \(W) + g.x] = s;
}
"""

func cpuValue(_ x: UInt32, _ y: UInt32, _ seed: UInt32) -> UInt32 {
    var s = (x &* 73856093) ^ (y &* 19349663) ^ seed
    for i in 0..<UInt32(ITERS) { s ^= s << 13; s ^= s >> 17; s ^= s << 5; s = s &+ i }
    return s
}

guard let dev = MTLCreateSystemDefaultDevice() else { print("no Metal device"); exit(2) }
print("device: \(dev.name)")
let lib = try dev.makeLibrary(source: src, options: nil)
let pso = try dev.makeComputePipelineState(function: lib.makeFunction(name: "k")!)
let q = dev.makeCommandQueue()!
let out = dev.makeBuffer(length: W * H * 4, options: .storageModeShared)!
let tg = MTLSize(width: 16, height: 16, depth: 1)
let grid = MTLSize(width: W, height: H, depth: 1)

var frames = 0, checks = 0, wrong = 0
let t0 = Date()
var last = t0
var checkTime = 0.0
while Date().timeIntervalSince(t0) < seconds {
    var seed = UInt32(truncatingIfNeeded: frames &* 2654435761)
    let cb = q.makeCommandBuffer()!
    let enc = cb.makeComputeCommandEncoder()!
    enc.setComputePipelineState(pso)
    enc.setBuffer(out, offset: 0, index: 0)
    enc.setBytes(&seed, length: 4, index: 1)
    enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
    enc.endEncoding()
    cb.commit()
    frames += 1
    if checkEvery > 0 && frames % checkEvery == 0 {
        cb.waitUntilCompleted()
        let c0 = Date()
        checks += 1
        let p = out.contents().bindMemory(to: UInt32.self, capacity: W * H)
        var bad = 0
        for y in stride(from: 0, to: H, by: 7) {
            for x in stride(from: 0, to: W, by: 7) where p[y * W + x] != cpuValue(UInt32(x), UInt32(y), seed) {
                bad += 1
            }
        }
        wrong += bad
        if bad > 0 { print("frame \(frames): \(bad) wrong samples") }
        checkTime += Date().timeIntervalSince(c0)
    }
    if Date().timeIntervalSince(last) >= 30 {
        last = Date()
        print("\(Int(last.timeIntervalSince(t0))) s: \(frames) frames, \(checks) checks, \(wrong) wrong")
    }
}
let fin = q.makeCommandBuffer()!; fin.commit(); fin.waitUntilCompleted()
let t = Date().timeIntervalSince(t0)
let rate = Double(frames) * Double(W * H * ITERS) / t / 1e9
print(String(format: "frames %d in %.1f s (%.1f fps, %.2f Gpix-iter/s), checks %d, wrong samples %d",
             frames, t, Double(frames) / t, rate, checks, wrong))
if checks > 0 {
    print(String(format: "CPU check time %.2f ms per check (GPU idle meanwhile), every %d frames",
                 checkTime * 1000 / Double(checks), checkEvery))
}
print(wrong == 0 ? "STRESS_PASS" : "STRESS_FAIL")
exit(wrong == 0 ? 0 : 1)
