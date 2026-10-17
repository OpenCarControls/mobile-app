import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';

let scene, camera, renderer, mixer, clock;
let carModel;
let targetTheta = 45 * Math.PI / 180;
let currentTheta = 45 * Math.PI / 180;
let actions = {};
let cachedMaterials = {};
let needsRender = true;
let activeMaterialScrolls = {};
// Tweens driven by the render loop so Flutter only has to send target values.
// meshFades: { meshName: { current, target, durationS } }
// materialPulses: { materialName: { t, active, maxIntensity, scrollX, durationS } }
let meshFades = {};
let materialPulses = {};
// Periodic toggle between two sets of material definitions (e.g. hazards).
let blink = null; // { active, periodS, on: [...], off: [...], elapsed, isOn }

let isInitialized = false;
let animationFrameId = null;
let currentConfig = null;

// Notify Flutter that the renderer logic is loaded
window.addEventListener("flutterInAppWebViewPlatformReady", function(event) {
    window.flutter_inappwebview.callHandler('onRendererReady');
});

// Fallback for debugging outside webview
window.addEventListener('load', () => {
    if (!window.flutter_inappwebview) {
        setTimeout(() => {
            if (window.flutter_inappwebview) {
                window.flutter_inappwebview.callHandler('onRendererReady');
            }
        }, 500);
    }
});

window.initRenderer = function(configJson) {
    currentConfig = JSON.parse(configJson);

    if (isInitialized) {
        // Cleanup old scene
        if (animationFrameId !== null) cancelAnimationFrame(animationFrameId);
        if (scene) {
            scene.traverse((child) => {
                if (child.geometry) child.geometry.dispose();
                if (child.material) {
                    if (Array.isArray(child.material)) {
                        child.material.forEach(mat => mat.dispose());
                    } else {
                        child.material.dispose();
                    }
                }
            });
        }
        if (renderer) {
            renderer.dispose();
            if (renderer.domElement && renderer.domElement.parentNode) {
                renderer.domElement.parentNode.removeChild(renderer.domElement);
            }
        }
        // Reset state
        carModel = null;
        cachedMaterials = {};
        actions = {};
        mixer = null;
        meshFades = {};
        materialPulses = {};
        blink = null;
        activeMaterialScrolls = {};
        window.animStates = {};
        window._isFirstStatePush = true;
    }

    isInitialized = true;
    init();
    animate();
};

function init() {
    // Setup Scene
    scene = new THREE.Scene();

    // Setup Orthographic Camera
    const aspect = window.innerWidth / window.innerHeight;
    const frustumSize = currentConfig.camera?.frustumSize || 6;
    camera = new THREE.OrthographicCamera(
        frustumSize * aspect / -2,
        frustumSize * aspect / 2,
        frustumSize / 2,
        frustumSize / -2,
        0.1,
        1000
    );

    // Initial camera position
    const radius = currentConfig.camera?.position?.radius || 10;
    targetTheta = currentConfig.camera?.position?.theta || (45 * Math.PI / 180);
    currentTheta = targetTheta;
    const phi = currentConfig.camera?.position?.phi || (60 * Math.PI / 180);

    camera.position.setFromSphericalCoords(radius, phi, targetTheta);
    camera.lookAt(0, 0, 0);

    // Setup Renderer
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(window.innerWidth, window.innerHeight);
    renderer.setPixelRatio(window.devicePixelRatio);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    document.body.appendChild(renderer.domElement);

    // Lighting
    const ambColor = currentConfig.lighting?.ambientLight?.color || 0xffffff;
    const ambInt = currentConfig.lighting?.ambientLight?.intensity || 1.2;
    const ambientLight = new THREE.AmbientLight(ambColor, ambInt);
    scene.add(ambientLight);

    const dirColor = currentConfig.lighting?.directionalLight?.color || 0xffffff;
    const dirInt = currentConfig.lighting?.directionalLight?.intensity || 3.0;
    const directionalLight = new THREE.DirectionalLight(dirColor, dirInt);
    const pos = currentConfig.lighting?.directionalLight?.position || {x: 10, y: 20, z: 10};
    directionalLight.position.set(pos.x, pos.y, pos.z);
    scene.add(directionalLight);

    // Clock for animations
    clock = new THREE.Clock();

    // Load Model
    const loader = new GLTFLoader();
    loader.setMeshoptDecoder(MeshoptDecoder);
    const modelPath = currentConfig.model?.path || '../cars/egmp/2022_kia_ev6.glb';
    const fadeStart = currentConfig.shader?.fadeStart || 4.0;
    const fadeEnd = currentConfig.shader?.fadeEnd || 4.25;
    loader.load(modelPath, (gltf) => {
        carModel = gltf.scene;
        scene.add(carModel);

        // Cache materials
        carModel.traverse((child) => {
            if (child.isMesh && child.material) {
                const materials = Array.isArray(child.material) ? child.material : [child.material];
                materials.forEach(mat => {
                    if (!cachedMaterials[mat.name]) cachedMaterials[mat.name] = [];
                    if (!cachedMaterials[mat.name].includes(mat)) {
                        cachedMaterials[mat.name].push(mat);
                    }
                });
            }
        });

        // Setup Animations
        mixer = new THREE.AnimationMixer(carModel);
        gltf.animations.forEach((clip) => {
            const action = mixer.clipAction(clip);
            action.clampWhenFinished = true;
            action.loop = THREE.LoopOnce;
            actions[clip.name] = action;
        });

        // Removed the custom distance fade shader as requested.

        // Notify Flutter that model is loaded
        if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('onModelLoaded');
        }
    }, undefined, (error) => {
        console.error('Error loading model:', error);
    });

    window.addEventListener('resize', onWindowResize, false);
}

function onWindowResize() {
    const aspect = window.innerWidth / window.innerHeight;
    const frustumSize = currentConfig.camera?.frustumSize || 6;
    camera.left = -frustumSize * aspect / 2;
    camera.right = frustumSize * aspect / 2;
    camera.top = frustumSize / 2;
    camera.bottom = -frustumSize / 2;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
    needsRender = true;
    window._forceRenderFrames = 5;
}

function animate() {
    animationFrameId = requestAnimationFrame(animate);
    const delta = clock.getDelta();

    let shouldRender = needsRender;
    needsRender = false;

    // Tween camera theta
    let isCameraMoving = false;
    if (Math.abs(targetTheta - currentTheta) > 0.001) {
        currentTheta += (targetTheta - currentTheta) * 0.05;
        camera.position.setFromSphericalCoords(10, 60 * Math.PI / 180, currentTheta);
        camera.lookAt(0, 0, 0);
        shouldRender = true;
        isCameraMoving = true;
    }

    let isAnimating = false;
    if (mixer) {
        mixer.update(delta);
        for (const name in actions) {
            if (actions[name].isRunning()) {
                shouldRender = true;
                isAnimating = true;
                break;
            }
        }
    }

    const isTweening = updateTweens(delta);
    if (isTweening) shouldRender = true;
    if (updateBlink(delta)) shouldRender = true;

    let isMoving = isCameraMoving || isAnimating || isTweening;
    
    if (window._forceRenderFrames > 0) {
        shouldRender = true;
        window._forceRenderFrames--;
    }

    if (window._statePending && !isMoving && window._forceRenderFrames === 0) {
        window._statePending = false;
        if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('onStateSettled');
        }
    } else if (isMoving || window._forceRenderFrames > 0) {
        window._statePending = true;
    }

    for (const name in activeMaterialScrolls) {
        const speed = activeMaterialScrolls[name];
        if (speed && cachedMaterials[name]) {
            const mats = cachedMaterials[name];
            mats.forEach(mat => {
                if (mat.map) {
                    mat.map.offset.x += delta * (speed.x || 0);
                    mat.map.offset.y += delta * (speed.y || 0);
                }
                if (mat.emissiveMap) {
                    mat.emissiveMap.offset.x += delta * (speed.x || 0);
                    mat.emissiveMap.offset.y += delta * (speed.y || 0);
                }
            });
            shouldRender = true;
        }
    }

    if (shouldRender) {
        renderer.render(scene, camera);
    }
}

function easeInOut(t) {
    return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}

// Advances mesh fades and material pulses. Returns true while any is moving.
function updateTweens(delta) {
    let moving = false;

    for (const name in meshFades) {
        const fade = meshFades[name];
        if (fade.current === fade.target) continue;
        const step = delta / fade.durationS;
        fade.current = fade.target > fade.current
            ? Math.min(fade.target, fade.current + step)
            : Math.max(fade.target, fade.current - step);
        window.setMeshOpacity(name, fade.current);
        moving = true;
    }

    for (const name in materialPulses) {
        const pulse = materialPulses[name];
        const target = pulse.active ? 1 : 0;
        if (pulse.t === target) continue;
        const step = delta / pulse.durationS;
        pulse.t = pulse.active ? Math.min(1, pulse.t + step) : Math.max(0, pulse.t - step);
        applyMaterialPulse(name, pulse);
        moving = true;
    }

    return moving;
}

function applyMaterialPulse(name, pulse) {
    const mats = cachedMaterials[name];
    if (mats) {
        mats.forEach(mat => {
            mat.emissiveIntensity = easeInOut(pulse.t) * pulse.maxIntensity;
        });
    }
    // Scroll while visible; reset the texture offset once fully faded out.
    window.setMaterialScroll(name, pulse.t > 0 ? pulse.scrollX : 0, 0, pulse.t === 0);
}

function applyMaterialDefs(defs) {
    defs.forEach((matDef) => {
        if (matDef.emissive !== undefined) {
            setMaterialEmissive(matDef.name, matDef.emissive, matDef.intensity || 0);
        }
        if (matDef.color !== undefined) {
            setMaterialColor(matDef.name, matDef.color);
        }
        if (matDef.visible !== undefined) {
            window.setMaterialVisibility(matDef.name, matDef.visible);
        }
    });
}

// Toggles the blink "on"/"off" material sets. Returns true when it changed
// something that needs a render. Blinking is not "moving": it must not hold
// back onStateSettled, or the snapshot would never be taken.
function updateBlink(delta) {
    if (!blink || !blink.active) return false;
    blink.elapsed += delta;
    if (blink.elapsed < blink.periodS) return false;
    blink.elapsed = 0;
    blink.isOn = !blink.isOn;
    applyMaterialDefs(blink.isOn ? blink.on : blink.off);
    return true;
}

function setMaterialEmissive(name, hexColor, intensity) {
    const mats = cachedMaterials[name];
    if (mats) {
        mats.forEach(mat => {
            mat.emissive.setHex(hexColor);
            mat.emissiveIntensity = intensity;
        });
    }
}

function setMaterialColor(name, hexColor) {
    const mats = cachedMaterials[name];
    if (mats) {
        mats.forEach(mat => {
            mat.color.setHex(hexColor);
        });
    }
}

// Material APIs for Flutter
window.setMaterialVisibility = function(name, isVisible) {
    const mats = cachedMaterials[name];
    if (mats) {
        mats.forEach(mat => {
            mat.visible = isVisible;
        });
        needsRender = true;
    }
};

window.setMaterialScroll = function(name, speedX, speedY = 0, resetOffset = false) {
    if (speedX === 0 && speedY === 0) {
        delete activeMaterialScrolls[name];
    } else {
        activeMaterialScrolls[name] = { x: speedX, y: speedY };
    }
    
    if (resetOffset) {
        const mats = cachedMaterials[name];
        if (mats) {
            mats.forEach(mat => {
                if (mat.map) mat.map.offset.set(0, 0);
                if (mat.emissiveMap) mat.emissiveMap.offset.set(0, 0);
            });
        }
    }
    
    needsRender = true;
};

window.setMaterialColorAPI = function(name, hexColor) {
    setMaterialColor(name, hexColor);
    needsRender = true;
};

window.setMaterialEmissiveAPI = function(name, hexColor, intensity) {
    setMaterialEmissive(name, hexColor, intensity);
    needsRender = true;
};

window.setMeshOpacity = function(meshName, opacity) {
    if (!carModel) return;
    const group = carModel.getObjectByName(meshName);
    if (group) {
        group.traverse((child) => {
            if (child.isMesh && child.material) {
                if (!child.userData.hasClonedMaterial) {
                    if (Array.isArray(child.material)) {
                        child.material = child.material.map(m => {
                            const clone = m.clone();
                            if (cachedMaterials[m.name]) cachedMaterials[m.name].push(clone);
                            return clone;
                        });
                    } else {
                        const m = child.material;
                        const clone = m.clone();
                        if (cachedMaterials[m.name]) cachedMaterials[m.name].push(clone);
                        child.material = clone;
                    }
                    child.userData.hasClonedMaterial = true;
                }
                const materials = Array.isArray(child.material) ? child.material : [child.material];
                materials.forEach(mat => {
                    let needsUpdate = false;
                    if (!mat.transparent) {
                        mat.transparent = true;
                        needsUpdate = true;
                    }
                    const newDepthWrite = true; // Force depth write to fix inner cable clipping
                    if (mat.depthWrite !== newDepthWrite) {
                        mat.depthWrite = newDepthWrite;
                        needsUpdate = true;
                    }
                    mat.opacity = opacity;
                    if (needsUpdate) mat.needsUpdate = true;
                });
            }
        });
        group.visible = opacity > 0;
    }
    needsRender = true;
};

// Exposed function for Flutter to call
window.getSnapshot = function() {
    if (renderer && scene && camera) {
        renderer.render(scene, camera);
        return renderer.domElement.toDataURL('image/png');
    }
    return null;
};

window._isFirstStatePush = true;

// Accepts either a state object or its JSON string.
window.setVehicleState = function (state) {
    if (!carModel) return;

    needsRender = true;
    window._statePending = true;
    window._forceRenderFrames = 10;
    const payload = typeof state === 'string' ? JSON.parse(state) : state;
    const isInstant = window._isFirstStatePush;
    window._isFirstStatePush = false;

    // 1. Camera
    if (payload.camera && payload.camera.targetTheta !== undefined) {
        targetTheta = payload.camera.targetTheta;
        if (isInstant) {
            currentTheta = targetTheta;
            camera.position.setFromSphericalCoords(10, 60 * Math.PI / 180, currentTheta);
            camera.lookAt(0, 0, 0);
        }
    }

    // 2. Mesh Visibility and Opacity
    if (payload.meshVisibility) {
        for (const [meshName, visible] of Object.entries(payload.meshVisibility)) {
            // If the payload specifies a boolean, use standard visibility
            if (typeof visible === 'boolean') {
                carModel.traverse((child) => {
                    if (child.name === meshName) {
                        child.visible = visible;
                    }
                });
            }
        }
    }
    
    // Target opacities, faded in the render loop.
    // { meshName: opacity } or { meshName: { opacity, durationMs } }
    if (payload.meshOpacity) {
        for (const [meshName, value] of Object.entries(payload.meshOpacity)) {
            const target = typeof value === 'number' ? value : value.opacity;
            const durationS = (value.durationMs ?? 500) / 1000;
            const fade = meshFades[meshName] ?? { current: isInstant ? target : 0 };
            fade.target = target;
            fade.durationS = durationS;
            if (isInstant) fade.current = target;
            meshFades[meshName] = fade;
            window.setMeshOpacity(meshName, fade.current);
        }
    }

    // 3. Materials
    if (payload.materials) {
        applyMaterialDefs(payload.materials);
        payload.materials.forEach((matDef) => {
            if (matDef.scrollX !== undefined || matDef.scrollY !== undefined) {
                window.setMaterialScroll(matDef.name, matDef.scrollX || 0, matDef.scrollY || 0, matDef.resetScroll === true);
            }
        });
    }

    // Emissive fade + texture scroll, eased in the render loop.
    // { materialName: { active, maxIntensity, scrollX, durationMs } }
    if (payload.materialPulses) {
        for (const [name, def] of Object.entries(payload.materialPulses)) {
            const pulse = materialPulses[name] ?? { t: 0 };
            pulse.active = def.active;
            pulse.maxIntensity = def.maxIntensity ?? 1;
            pulse.scrollX = def.scrollX ?? 0;
            pulse.durationS = (def.durationMs ?? 500) / 1000;
            if (isInstant) pulse.t = def.active ? 1 : 0;
            materialPulses[name] = pulse;
            applyMaterialPulse(name, pulse);
        }
    }

    // { active, periodMs, on: [materialDefs], off: [materialDefs] }
    if (payload.blink) {
        const wasActive = blink?.active === true;
        blink = {
            active: payload.blink.active,
            periodS: (payload.blink.periodMs ?? 500) / 1000,
            on: payload.blink.on ?? [],
            off: payload.blink.off ?? [],
            elapsed: wasActive ? blink.elapsed : 0,
            isOn: wasActive ? blink.isOn : payload.blink.active,
        };
        applyMaterialDefs(blink.isOn && blink.active ? blink.on : blink.off);
    }

    // 4. Animations
    if (payload.animations) {
        if (!window.animStates) window.animStates = {};

        for (const animName in payload.animations) {
            const isOpen = payload.animations[animName];
            const action = actions[animName];
            
            if (!action) continue;
            if (window.animStates[animName] === isOpen) continue;

            // On first load, if the state is closed, record it and skip snap
            if (window.animStates[animName] === undefined && !isOpen) {
                window.animStates[animName] = isOpen;
                continue;
            }

            window.animStates[animName] = isOpen;
            action.paused = false;
            action.timeScale = isOpen ? 1 : -1;

            if (isOpen) {
                action.play();
                if (isInstant) {
                    action.time = action.getClip().duration;
                }
            } else {
                if (action.time === 0) action.time = action.getClip().duration;
                action.play();
                if (isInstant) {
                    action.time = 0;
                }
            }
        }
    }
};
