import MetalKit
import SwiftUI

private final class PointResolutionMTKView: MTKView {
    var renderScale: CGFloat = 1 {
        didSet {
            guard renderScale != oldValue else { return }
            updateDrawableSize()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        drawableSize = CGSize(
            width: max(1, (bounds.width * renderScale).rounded()),
            height: max(1, (bounds.height * renderScale).rounded())
        )
    }
}

struct MetalGameView: UIViewRepresentable {
    @ObservedObject var model: GameModel
    var onFallbackRequested: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = PointResolutionMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0.006, 0.009, 0.018, 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.autoResizeDrawable = false
        view.renderScale = model.renderResolution.scale

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        view.addGestureRecognizer(doubleTap)

        let waterTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleWaterTap(_:))
        )
        waterTap.cancelsTouchesInView = false
        waterTap.require(toFail: doubleTap)
        view.addGestureRecognizer(waterTap)

        do {
            let renderer = try MetalRayRenderer(view: view, audio: model.audio)
            context.coordinator.renderer = renderer
            renderer.onFPSUpdate = model.showsFPS ? context.coordinator.onFPSUpdate : nil
            renderer.onToolStatusUpdate = { [weak model] status in
                model?.reportToolStatus(status)
            }
            renderer.onNearbyLightUpdate = { [weak model] fixture in
                model?.reportNearbyLight(fixture)
            }
            renderer.onCoverStatusUpdate = { [weak model] isNear in
                Task { @MainActor in
                    model?.updateCoverStatus(isNear: isNear)
                }
            }
            renderer.onNPCHealthsUpdate = { [weak model] healths in
                Task { @MainActor in
                    model?.updateNPCHealths(healths)
                }
            }
            renderer.onScoreUpdate = { [weak model] points in
                Task { @MainActor in
                    model?.addScore(points)
                }
            }
            renderer.onDamageTaken = { [weak model] damage in
                Task { @MainActor in
                    model?.takeDamage(damage)
                }
            }
            renderer.onWaveUpdate = { [weak model] wave, remaining, total, isIntermission, intermissionTime in
                Task { @MainActor in
                    model?.updateWaveStatus(
                        wave: wave,
                        remaining: remaining,
                        total: total,
                        intermission: isIntermission,
                        intermissionTime: intermissionTime
                    )
                }
            }
            view.delegate = renderer
        } catch {
            if let onFallbackRequested {
                DispatchQueue.main.async {
                    onFallbackRequested()
                }
            } else {
                context.coordinator.showRendererError(error, in: view)
            }
        }

        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        (view as? PointResolutionMTKView)?.renderScale = model.renderResolution.scale
        context.coordinator.invertsCameraY = model.invertsCameraY
        context.coordinator.renderer?.isPlayerDead = (model.playerHealth <= 0)
        context.coordinator.renderer?.onFPSUpdate = model.showsFPS
            ? context.coordinator.onFPSUpdate
            : nil
        context.coordinator.renderer?.isSplitScreenMode = model.multiplayer.isConnected && model.multiplayer.role == .full3DRender
        let isPaused = model.gameState != .playing
        context.coordinator.renderer?.setInput(
            joystick: model.joystick,
            cameraMode: model.cameraMode,
            rayBouncesEnabled: true,
            heldTool: model.heldTool,
            lightStates: model.lightStates,
            jumpRequestID: model.jumpRequestID,
            isSlowMotionActive: model.isSlowMotionActive,
            warpRequestID: model.warpRequestID,
            requestedWarpPosition: model.requestedWarpPosition,
            isPaused: isPaused,
            resetRequestID: model.resetRequestID,
            isCoverActive: model.isCoverActive,
            shieldAngleOffset: model.shieldAngleOffset,
            respawnRequestID: model.respawnRequestID
        )
    }

    final class Coordinator: NSObject {
        var renderer: MetalRayRenderer?
        var invertsCameraY = false
        let onFPSUpdate: (Double) -> Void

        init(model: GameModel) {
            onFPSUpdate = { [weak model] framesPerSecond in
                Task { @MainActor in
                    model?.reportFPS(framesPerSecond)
                }
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            renderer?.rotateCamera(
                deltaX: Float(translation.x),
                deltaY: Float(translation.y) * (invertsCameraY ? -1 : 1)
            )
            gesture.setTranslation(.zero, in: view)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            renderer?.resetCamera()
        }

        @objc func handleWaterTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view else { return }
            renderer?.disturbWater(
                screenPoint: gesture.location(in: view),
                viewSize: view.bounds.size
            )
        }

        func showRendererError(_ error: Error, in view: MTKView) {
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "Metal Ray Tracing no disponible\n\(error.localizedDescription)"
            label.textColor = .white
            label.textAlignment = .center
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .headline)
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
    }
}
