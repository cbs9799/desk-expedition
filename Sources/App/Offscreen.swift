import Metal
import SpriteKit

/// Renders the strip scene without a window (snapshots and frame dumps for checking animation).
@MainActor
final class StripOffscreen {
    let scene: StripScene
    private let renderer: SKRenderer
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let texture: MTLTexture
    private var time: TimeInterval = 0
    let scale: CGFloat

    init?(store: GameStore, scale: CGFloat = 2) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        self.scale = scale
        scene = StripScene(size: CGSize(width: StripLayout.width, height: StripLayout.height))
        scene.store = store
        scene.scaleMode = .fill
        renderer = SKRenderer(device: device)
        renderer.scene = scene
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                            width: Int(StripLayout.width * scale),
                                                            height: Int(StripLayout.height * scale), mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        texture = tex
    }

    /// Advances the scene (actions, emitters, and the presentation logic) by `dt` seconds.
    func step(_ dt: TimeInterval) {
        time += dt
        renderer.update(atTime: time)
    }

    /// Renders a frame on the GPU without reading it back (what the live view does each frame).
    func renderOnly() -> Bool {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer() else { return false }
        renderer.render(withViewport: CGRect(x: 0, y: 0, width: texture.width, height: texture.height),
                        commandBuffer: cb, renderPassDescriptor: pass)
        cb.commit()
        cb.waitUntilCompleted()
        return true
    }

    func image() -> CGImage? {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer() else { return nil }
        renderer.render(withViewport: CGRect(x: 0, y: 0, width: texture.width, height: texture.height),
                        commandBuffer: cb, renderPassDescriptor: pass)
        cb.commit()
        cb.waitUntilCompleted()
        let w = texture.width, h = texture.height, rowBytes = w * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * h)
        texture.getBytes(&bytes, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
