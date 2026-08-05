import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

let scene, camera, renderer, mixer, clock;
let carModel;
let targetTheta = 45 * Math.PI / 180;
let currentTheta = 45 * Math.PI / 180;
let actions = {};
let cachedMaterials = {};
let needsRender = true;

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
    const modelPath = currentConfig.model?.path || '../cars/egmp/2022_kia_ev6.glb';
    const fadeStart = currentConfig.shader?.fadeStart || 4.0;
    const fadeEnd = currentConfig.shader?.fadeEnd || 4.25;
    loader.load(modelPath, (gltf) => {
        carModel = gltf.scene;
        scene.add(carModel);

        // Cache materials
        carModel.traverse((child) => {
            if (child.isMesh && child.material) {
                cachedMaterials[child.material.name] = child.material;
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

        // Setup Custom Shader for fading outside 4m radius
        carModel.traverse((child) => {
            if (child.isMesh && child.material) {
                // Ensure material is transparent to allow fading
                child.material.transparent = true;

                child.material.onBeforeCompile = (shader) => {
                    shader.vertexShader = shader.vertexShader.replace(
                        'void main() {',
                        `
                        varying vec3 vMyWorldPos;
                        void main() {
                        `
                    );
                    shader.vertexShader = shader.vertexShader.replace(
                        '#include <worldpos_vertex>',
                        `
                        #include <worldpos_vertex>
                        vMyWorldPos = (modelMatrix * vec4(transformed, 1.0)).xyz;
                        `
                    );

                    shader.fragmentShader = shader.fragmentShader.replace(
                        'void main() {',
                        `
                        varying vec3 vMyWorldPos;
                        void main() {
                        `
                    );
                    shader.fragmentShader = shader.fragmentShader.replace(
                        '#include <dithering_fragment>',
                        `
                        #include <dithering_fragment>
                        float dist = length(vMyWorldPos);
                        float fadeAlpha = smoothstep(${fadeEnd.toFixed(2)}, ${fadeStart.toFixed(2)}, dist);
                        gl_FragColor.a *= fadeAlpha;
                        `
                    );
                };
            }
        });

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
    const frustumSize = 4.5;
    camera.left = -frustumSize * aspect / 2;
    camera.right = frustumSize * aspect / 2;
    camera.top = frustumSize / 2;
    camera.bottom = -frustumSize / 2;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
}

function animate() {
    animationFrameId = requestAnimationFrame(animate);
    const delta = clock.getDelta();

    let shouldRender = needsRender;
    needsRender = false;

    // Tween camera theta
    if (Math.abs(targetTheta - currentTheta) > 0.001) {
        currentTheta += (targetTheta - currentTheta) * 0.05;
        camera.position.setFromSphericalCoords(10, 60 * Math.PI / 180, currentTheta);
        camera.lookAt(0, 0, 0);
        shouldRender = true;
    }

    if (mixer) {
        mixer.update(delta);
        for (const name in actions) {
            if (actions[name].isRunning()) {
                shouldRender = true;
                break;
            }
        }
    }

    if (shouldRender) {
        renderer.render(scene, camera);
    }
}

function setMaterialEmissive(name, hexColor, intensity) {
    const mat = cachedMaterials[name];
    if (mat) {
        mat.emissive.setHex(hexColor);
        mat.emissiveIntensity = intensity;
    }
}

function setMaterialColor(name, hexColor) {
    const mat = cachedMaterials[name];
    if (mat) {
        mat.color.setHex(hexColor);
    }
}

// Exposed function for Flutter to call
window.setVehicleState = function (stateJson) {
    if (!carModel) return;

    needsRender = true;
    const payload = JSON.parse(stateJson);

    // 1. Camera
    if (payload.camera && payload.camera.targetTheta !== undefined) {
        targetTheta = payload.camera.targetTheta;
    }

    // 2. Mesh Visibility
    if (payload.meshVisibility) {
        carModel.traverse((child) => {
            if (payload.meshVisibility.hasOwnProperty(child.name)) {
                child.visible = payload.meshVisibility[child.name];
            }
        });
    }

    // 3. Materials
    if (payload.materials) {
        payload.materials.forEach((matDef) => {
            if (matDef.emissive !== undefined) {
                setMaterialEmissive(matDef.name, matDef.emissive, matDef.intensity || 0);
            }
            if (matDef.color !== undefined) {
                setMaterialColor(matDef.name, matDef.color);
            }
        });
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
            } else {
                if (action.time === 0) action.time = action.getClip().duration;
                action.play();
            }
        }
    }
};
