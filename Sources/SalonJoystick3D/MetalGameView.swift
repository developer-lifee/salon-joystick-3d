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
        view.preferredFramesPerSecond = model.effectiveTargetFPS
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.autoResizeDrawable = false
        view.renderScale = model.effectiveRenderScale

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
            applyResolution(to: view, renderer: renderer)
            renderer.playerScore = model.playerScore
            renderer.onRainbowGateStatusUpdate = { [weak model] unlocked, current, target in
                Task { @MainActor in
                    model?.updateRainbowGateStatus(unlocked: unlocked, current: current, target: target)
                }
            }
            renderer.onFPSUpdate = model.showsFPS ? context.coordinator.onFPSUpdate : nil
            renderer.onToolStatusUpdate = { [weak model] status in
                model?.reportToolStatus(status)
            }
            renderer.onNearbyLightUpdate = { [weak model] fixture in
                model?.reportNearbyLight(fixture)
            }
            renderer.onFlashlightBatteryUpdate = { [weak model] battery in
                Task { @MainActor in
                    if model?.flashlightBattery != battery { model?.flashlightBattery = battery }
                }
            }
            renderer.onLaserBatteryUpdate = { [weak model] battery in
                Task { @MainActor in
                    if model?.laserBattery != battery { model?.laserBattery = battery }
                }
            }
            renderer.onMirrorHeatUpdate = { [weak model] heat, overheated in
                Task { @MainActor in
                    if model?.mirrorHeat != heat { model?.mirrorHeat = heat }
                    if model?.mirrorOverheated != overheated { model?.mirrorOverheated = overheated }
                }
            }
            renderer.onCoverStatusUpdate = { [weak model] isNear in
                Task { @MainActor in
                    model?.updateCoverStatus(isNear: isNear)
                }
            }
            renderer.onUnderwaterStatusUpdate = { [weak model] inWater in
                Task { @MainActor in
                    model?.isUnderwater = inWater
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
            renderer.onLocalPlayerTransformUpdate = { [weak model] pos, yaw in
                Task { @MainActor in
                    model?.updateLocalTransform(position: pos, yaw: yaw)
                }
            }
            renderer.isAuthorityForNPCs = model.isHost
            renderer.onNPCSyncUpdate = { [weak model] positions, healths, wave, remaining, total, isIntermission, intermissionTime, laserStarts, laserEnds in
                Task { @MainActor in
                    model?.npcPositions = positions
                    model?.npcHealths = healths
                    model?.broadcastEnemySync(
                        positions: positions,
                        healths: healths,
                        wave: wave,
                        remaining: remaining,
                        total: total,
                        isIntermission: isIntermission,
                        intermissionTime: intermissionTime,
                        laserStarts: laserStarts,
                        laserEnds: laserEnds
                    )
                }
            }
            renderer.onBotDamageToRemotePlayer = { [weak model] damage in
                Task { @MainActor in
                    model?.sendBotDamageToClient(damage)
                }
            }
            renderer.onRemoteNPCEliminated = { [weak model] points in
                Task { @MainActor in
                    model?.sendScoreAwardToClient(points)
                }
            }
            renderer.onClientNPCHit = { [weak model] botIndex, damage in
                Task { @MainActor in
                    model?.sendEnemyHit(index: botIndex, damage: damage)
                }
            }
            renderer.onNearRecoveryConsoleUpdate = { [weak model] isNear in
                Task { @MainActor in
                    model?.isNearRecoveryConsole = isNear
                }
            }
            renderer.onNearFuseTerminalUpdate = { [weak model] isNear in
                Task { @MainActor in
                    model?.isNearFuseTerminal = isNear
                }
            }
            renderer.on3DChestChallengeUpdate = { [weak model] chestID, remaining, timer in
                Task { @MainActor in
                    model?.active3DChestID = chestID
                    model?.active3DChestRemaining = remaining
                    model?.active3DChestTimer = timer
                }
            }
            renderer.on3DChestUnlocked = { [weak model] chestID, pts in
                Task { @MainActor in
                    model?.handle3DChestUnlocked(chestID: chestID, points: pts)
                }
            }
            renderer.onNearChestUpdate = { [weak model] chestID in
                Task { @MainActor in
                    model?.nearbyChestID = chestID
                }
            }
            model.onOpenChestRequested = { [weak renderer, weak model] chestID in
                let pts = renderer?.openChestFromMinigame(chestID: chestID) ?? 0
                if pts > 0 {
                    Task { @MainActor in
                        model?.playerHealth = min(model?.maxPlayerHealth ?? 150, (model?.playerHealth ?? 100) + 35)
                        model?.playerShield = min(100, (model?.playerShield ?? 0) + 25)
                    }
                }
            }
            renderer.onRecoveryProgressUpdate = { [weak model] remaining, isBoosting in
                Task { @MainActor in
                    model?.updateRecoveryProgress(remaining: remaining, isBoosting: isBoosting)
                }
            }
            renderer.onRecoveryCompleted = { [weak model] in
                Task { @MainActor in
                    model?.completeRecovery(wasRevivedByTeammate: false)
                }
            }
            renderer.onMirrorReflectionKill = { [weak model] in
                Task { @MainActor in
                    model?.gameCenter.unlockAchievement("achievement_mirror_kill")
                }
            }
            renderer.onDroneDeflectionKill = { [weak model] in
                Task { @MainActor in
                    model?.gameCenter.unlockAchievement("achievement_drone_deflection")
                }
            }
            renderer.onQuantumPuzzleSolved = { [weak model] in
                Task { @MainActor in
                    model?.onQuantumPuzzleSolved()
                }
            }
            renderer.onCampaignVictory = { [weak model] in
                Task { @MainActor in
                    model?.onCampaignVictory()
                }
            }
            renderer.onSlideCompleted = { [weak model] in
                Task { @MainActor in
                    model?.gameCenter.unlockAchievement("achievement_water_slide")
                }
            }
            renderer.onCrossedRainbowGate = { [weak model] in
                Task { @MainActor in
                    model?.gameCenter.unlockAchievement("achievement_mirror_world")
                }
            }
            renderer.onColossusDefeated = { [weak model] in
                Task { @MainActor in
                    model?.gameCenter.unlockAchievement("achievement_colossus_defeat")
                }
            }
            renderer.onDeepDiveReached = { [weak model] in
                Task { @MainActor in
                    model?.gameCenter.unlockAchievement("achievement_deep_dive")
                }
            }
            model.onRemoteNPCSyncReceived = { [weak renderer] pos, healths, wave, rem, tot, inter, interTime, laserStarts, laserEnds in
                renderer?.applyRemoteNPCSync(
                    positions: pos,
                    healths: healths,
                    wave: wave,
                    remaining: rem,
                    total: tot,
                    isIntermission: inter,
                    intermissionTime: interTime,
                    laserStarts: laserStarts,
                    laserEnds: laserEnds
                )
            }
            model.onRemoteNPCHitReceived = { [weak renderer] botIndex, damage in
                renderer?.applyRemoteNPCDamage(index: botIndex, damage: damage)
            }
            renderer.onRemotePlayerHit = { [weak model] damage in
                Task { @MainActor in
                    model?.sendHitToRemotePlayer(damage: damage)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            renderer.onRemoteAgentHit = { [weak model] targetPeerID, damage in
                Task { @MainActor in
                    model?.sendHitToRemotePlayer(damage: damage, targetPeerID: targetPeerID)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            renderer.lumiBodyColor = model.lumiBodyRGB
            renderer.lumiCrestColor = model.lumiCrestRGB
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

    /// Con MetalFX el drawable va a resolución de salida y el ray tracing a la resolución interna elegida.
    private func applyResolution(to view: MTKView, renderer: MetalRayRenderer?) {
        let internalScale = model.effectiveRenderScale
        var outputScale = internalScale
        if model.metalFXUpscalingEnabled, renderer?.supportsMetalFXUpscaling == true {
            outputScale = max(internalScale, min(internalScale * 2, view.window?.screen.nativeScale ?? 3))
        }
        (view as? PointResolutionMTKView)?.renderScale = outputScale
        renderer?.internalRenderRatio = Float(internalScale / outputScale)
    }

    func updateUIView(_ view: MTKView, context: Context) {
        applyResolution(to: view, renderer: context.coordinator.renderer)
        if view.preferredFramesPerSecond != model.effectiveTargetFPS {
            view.preferredFramesPerSecond = model.effectiveTargetFPS
        }
        context.coordinator.invertsCameraY = model.invertsCameraY
        context.coordinator.cameraSensitivity = Float(model.cameraSensitivity)
        if model.playerScore == 0 {
            context.coordinator.renderer?.playerScore = 0
        } else {
            context.coordinator.renderer?.playerScore = max(context.coordinator.renderer?.playerScore ?? 0, model.playerScore)
        }
        context.coordinator.renderer?.isPlayerDead = (model.playerHealth <= 0 || model.isDefeated) && !model.isRecoveringInChamber
        context.coordinator.renderer?.isHost = model.isHost
        context.coordinator.renderer?.isRecoveringInChamber = model.isRecoveringInChamber
        context.coordinator.renderer?.remotePlayerIsRecovering = model.remotePlayerIsRecovering
        context.coordinator.renderer?.recoveryTimeRemaining = model.recoveryTimeRemaining
        context.coordinator.renderer?.onFPSUpdate = model.showsFPS
            ? context.coordinator.onFPSUpdate
            : nil
        context.coordinator.renderer?.isSplitScreenMode = (model.duoScreenMode == .squadCamera)
        let squadTarget = model.selectedSquadCameraAgent
        context.coordinator.renderer?.secondaryCameraPos = squadTarget.position + SIMD3<Float>(0, 1.38, 0) - SIMD3<Float>(sin(squadTarget.yaw), -0.18, cos(squadTarget.yaw)) * 2.2
        context.coordinator.renderer?.secondaryCameraFwd = simd_normalize(SIMD3<Float>(sin(squadTarget.yaw), -0.10, cos(squadTarget.yaw)))
        context.coordinator.renderer?.isAuthorityForNPCs = model.isHost
        let isVersus = model.isAnyMultiplayerConnected && (model.multiplayer.mode == .versus || model.multiplayer.mode == .lightBattle)
        context.coordinator.renderer?.isVersusMode = isVersus
        let spawnPos = model.localSpawnPosition
        let spawnYaw = model.localSpawnYaw
        context.coordinator.renderer?.initialSpawnPosition = spawnPos
        context.coordinator.renderer?.initialSpawnYaw = spawnYaw
        context.coordinator.renderer?.isRemotePlayerConnected = model.isAnyMultiplayerConnected
        context.coordinator.renderer?.remotePlayerPosition = model.remotePlayerPosition
        context.coordinator.renderer?.remotePlayerYaw = model.remotePlayerYaw
        context.coordinator.renderer?.lumiBodyColor = model.lumiBodyRGB
        context.coordinator.renderer?.lumiCrestColor = model.lumiCrestRGB
        context.coordinator.renderer?.remotePlayerHeldTool = model.remotePlayerHeldTool
        context.coordinator.renderer?.remotePlayerIsFiringLaser = model.remotePlayerIsFiringLaser
        context.coordinator.renderer?.remoteAgents = model.sortedRemoteAgents
        let isPaused = model.gameState != .playing || model.showsSettingsSheet || model.showsMultiplayerSheet || model.isEditingHUDLayout
        context.coordinator.renderer?.setInput(
            joystick: (model.isDefeated || isPaused) ? .zero : model.joystick,
            cameraMode: model.cameraMode,
            rayBouncesEnabled: model.advancedReflectionsEnabled,
            heldTool: model.isDefeated ? .none : model.heldTool,
            lightStates: model.lightStates,
            jumpRequestID: model.jumpRequestID,
            isSlowMotionActive: model.isSlowMotionActive,
            warpRequestID: model.warpRequestID,
            requestedWarpPosition: model.requestedWarpPosition,
            isPaused: isPaused,
            resetRequestID: model.resetRequestID,
            isCoverActive: model.isCoverActive,
            shieldAngleOffset: model.shieldAngleOffset,
            respawnRequestID: model.respawnRequestID,
            diveRequestID: model.diveRequestID
        )
    }

    final class Coordinator: NSObject {
        var renderer: MetalRayRenderer?
        var invertsCameraY = false
        var cameraSensitivity: Float = 1.0
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
                deltaX: Float(translation.x) * cameraSensitivity,
                deltaY: Float(translation.y) * (invertsCameraY ? -1 : 1) * cameraSensitivity
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
