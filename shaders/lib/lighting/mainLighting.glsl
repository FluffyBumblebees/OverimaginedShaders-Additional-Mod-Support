//Lighting Uniforms//
uniform float darknessLightFactor;

#ifdef HELD_LIGHTING
	uniform int heldBlockLightValue;
	uniform int heldBlockLightValue2;
#endif

//Lighting Includes//
#include "/lib/colors/lightAndAmbientColors.glsl"
#include "/lib/lighting/ggx.glsl"

#if defined OVERWORLD || defined END
    #include "/lib/lighting/shadowSampling.glsl"
#endif

#ifdef CLOUD_SHADOWS
    #include "/lib/atmospherics/cloudCoord.glsl"
#endif

//Lighting Variables//
float eyeBrightnessM2 = eyeBrightnessM * eyeBrightnessM;
float noonFactor20 = pow(noonFactor, 20.0);        
vec3 highlightColor = normalize(pow(lightColor, vec3(0.37))) * (0.5 + 1.3 * sunVisibility2) * (1.0 - 0.85 * rainFactor);

//Lighting//
void DoLighting(inout vec3 color, inout vec3 shadowMult, vec3 playerPos, vec3 viewPos, float lViewPos, vec3 normalM, vec2 lightmap,
                bool noSmoothLighting, bool noDirectionalShading, bool noVanillaAO, int subsurfaceMode,
                float smoothnessG, float highlightMult, float emission) {
    // Prepare Variables
    float lightmapY2 = pow2(lightmap.y);
    float lightmapYM = smoothstep1(lightmap.y);
    float subsurfaceHighlight = 0.0;
    vec3 ambientMult = vec3(1.0);
    vec3 shadowLighting = lightColor;
    vec3 nViewPos = normalize(viewPos);

    #if defined PERPENDICULAR_TWEAKS && defined SIDE_SHADOWING || defined DIRECTIONAL_SHADING
        float NdotN = dot(normalM, northVec);
        float absNdotN = abs(NdotN);
    #endif

    // Real-Time Shadows
    #if defined OVERWORLD || defined END
        float NdotL = dot(normalM, lightVec);
        float NdotLmax0 = max(NdotL, 0.0);
        float NdotLM = NdotLmax0 * 0.9999;

        #ifndef GBUFFERS_TEXTURED
                #ifdef GBUFFERS_TERRAIN
                    if (subsurfaceMode != 0) {
                        NdotLM = 1.0;
                    }
                #endif
            #if defined PERPENDICULAR_TWEAKS && defined SIDE_SHADOWING
                #ifdef GBUFFERS_TERRAIN
                     else
                #endif
                NdotLM = mix(NdotLM, (NdotL + 0.4) * 0.714, absNdotN * pow2(pow2(pow2(1.0 - NdotLM))));
            #endif
        #else
            NdotLM = 1.0;
        #endif

        if (shadowMult.r > 0.00001) {
            if (NdotLM > 0.0001) {
                float shadowLength = shadowDistance * 0.9166667 - length(vec4(playerPos.x, playerPos.y, playerPos.y, playerPos.z));

                if (shadowLength > 0.000001) {
                    float offset = 0.0009765;

                    vec3 playerPosM = playerPos;
                    
                    #if PIXEL_SHADOW > 0 && !defined GBUFFERS_HAND
                        playerPosM = floor((playerPosM + cameraPosition) * PIXEL_SHADOW + 0.001) / PIXEL_SHADOW - cameraPosition + 0.5 / PIXEL_SHADOW;
                    #endif

                    #ifndef GBUFFERS_TEXTURED
                        // Shadow bias without peter-panning
                        vec3 worldNormal = normalize(ViewToPlayer(normal*1000.0));
                        vec3 bias = worldNormal * min(0.12 + length(playerPos) / 200.0, 0.5) * (2.0 - NdotLmax0);

                        // Fix light leaking in caves
                        vec3 edgeFactor = 0.2 * (0.5 - fract(playerPosM + cameraPosition + worldNormal * 0.01));

                        #ifdef GBUFFERS_TERRAIN
                            #ifdef PERPENDICULAR_TWEAKS
                                if (subsurfaceMode == 2) bias *= vec3(0.0, 0.0, -0.75);
                                else
                            #endif
                            if (subsurfaceMode == 1) bias *= 1.0 - lightmapYM;
                        #endif
                        if (lightmapYM < 0.999) playerPosM += (1.0 - pow2(pow2(max(glColor.a, lightmapYM)))) * edgeFactor;
                        #ifdef GBUFFERS_WATER
                            bias *= 0.5;
                            playerPosM += (1.0 - lightmapYM) * edgeFactor;
                        #endif

                        playerPosM += bias;
                    #else
                        vec3 centerplayerPos = floor(playerPosM + cameraPosition) - cameraPosition + 0.5;
                        playerPosM = mix(centerplayerPos, playerPosM + vec3(0.0, 0.02, 0.0), lightmapYM);
                    #endif
                        
                    vec3 shadowPos = calculateShadowPos(playerPosM);

                    #ifdef TAA
                        float gradientNoise = InterleavedGradientNoise();
                    #else
                        float gradientNoise = 0.5;
                    #endif

                    bool leaves = false;
                    #ifdef GBUFFERS_TERRAIN
                        if (subsurfaceMode == 0) {
                            #if defined PERPENDICULAR_TWEAKS && defined SIDE_SHADOWING
                                offset *= 1.0 + pow2(absNdotN);
                            #endif
                        } else {
                            float VdotL = dot(nViewPos, lightVec);
                            float lightFactor = pow(clamp(VdotL, 0.0, 1.0), 10.0) * float(isEyeInWater == 0);
                            if (subsurfaceMode == 1) {
                                offset = 0.0010235 * lightmapYM + 0.0009765;
                                shadowPos.z -= max(NdotL * 0.0001, 0.0) * lightmapYM;
                                subsurfaceHighlight = lightFactor * 0.8;
                                #ifndef SHADOW_FILTERING
                                    shadowPos.z -= 0.0002;
                                #endif
                            } else {
                                leaves = true;
                                offset = 0.0005235 * lightmapYM + 0.0009765;
                                shadowPos.z -= 0.000175 * lightmapYM;
                                subsurfaceHighlight = lightFactor * 0.6;
                                #ifndef SHADOW_FILTERING
                                    NdotLM = mix(NdotL, NdotLM, 0.5);
                                #endif
                            }
                        }
                    #endif

                    shadowMult *= GetShadow(shadowPos, offset, gradientNoise, leaves);
                }

                float shadowSmooth = 16.0;
                if (shadowLength < shadowSmooth) {
                    float shadowMixer = max(shadowLength / shadowSmooth, 0.0);
                    #ifdef OVERWORLD
                        float skyLightshadowMult = pow2(pow2(lightmapY2));
                    #else
                        float skyLightshadowMult = 1.0;
                    #endif
                    shadowMult = mix(vec3(skyLightshadowMult), shadowMult, shadowMixer);
                    
                    #ifdef GBUFFERS_TERRAIN
                        if (subsurfaceMode != 0) {
                            shadowMixer *= shadowMixer;
                            if (subsurfaceMode == 1) NdotLM = mix(dot(lightVec, upVec) * 0.3 + 0.4, 1.0, shadowMixer);
                            else NdotLM = mix(NdotL * 0.45 + 0.55, NdotLM, pow2(shadowMixer));
                            subsurfaceHighlight = mix(0.0, subsurfaceHighlight, shadowMixer);
                        }
                    #endif
                }

                #ifdef CLOUD_SHADOWS
                    if (shadowMult.r > 0.0001) {
                        vec3 worldPos = playerPos + cameraPosition;

                        float EdotL = dot(eastVec, lightVec);
                        float EdotLM = tan(acos(EdotL));

                        float distToCloudLayer1 = CLOUD_ALT1 - worldPos.y;
                        float cloudOffset1 = distToCloudLayer1 / EdotLM;
                        vec2 cloudPos1 = GetRoundedCloudCoord(ModifyTracePos(worldPos + vec3(cloudOffset1, 0,0), CLOUD_ALT1).xz);
                        float cloudSample = texture2D(gaux3, cloudPos1).r;
                        cloudSample *= clamp(distToCloudLayer1 * 0.1, 0.0, 1.0);

                        #ifdef SECOND_CLOUD_LAYER
                            float distToCloudLayer2 = CLOUD_ALT2 - worldPos.y;
                            float cloudOffset2 = distToCloudLayer2 / EdotLM;
                            vec2 cloudPos2 = GetRoundedCloudCoord(ModifyTracePos(worldPos + vec3(cloudOffset2, 0,0), CLOUD_ALT2).xz);
                            float cloudSample2 = texture2D(gaux3, cloudPos2).r;
                            cloudSample2 *= clamp(distToCloudLayer2 * 0.1, 0.0, 1.0);

                            cloudSample = max(cloudSample, cloudSample2);
                        #endif
                        
                        shadowMult *= 1.0 - 0.85 * cloudSample * sqrt3(1.0 - abs(EdotL));
                    }
                #endif
            }

            shadowMult *= max(NdotLM * shadowTime, 0.0);
        }
    #endif

    // Blocklight
    #ifdef HELD_LIGHTING
        float heldLight = max(heldBlockLightValue, heldBlockLightValue2) - lViewPos;
        lightmap.x = max(lightmap.x, heldLight * 0.066666);
    #endif
    float lightmapXM;
    if (!noSmoothLighting) {
        float lightmapXMSteep = pow2(pow2(lightmap.x * lightmap.x))  * (2.30 - 0.25 * vsBrightness);
        float lightmapXMCalm = max((lightmap.x - 0.05) * 0.925, 0.0) * (2.00 + 0.25 * vsBrightness);
        lightmapXM = pow(lightmapXMSteep + lightmapXMCalm, 1.5);
    } else lightmapXM = lightmap.x * lightmap.x * 3.0;

    // Minimum Light
    #if !defined END && MINIMUM_LIGHT_MODE > 0
        #if MINIMUM_LIGHT_MODE == 1
            vec3 minLighting = vec3(0.05);
        #elif MINIMUM_LIGHT_MODE == 2
            vec3 minLighting = vec3(0.075 + vsBrightness * 0.145);
        #elif MINIMUM_LIGHT_MODE == 3
            vec3 minLighting = vec3(0.3);
        #elif MINIMUM_LIGHT_MODE == 4
            vec3 minLighting = vec3(0.5);
        #endif

        minLighting *= 1.0 - eyeBrightnessM2;
    #else
        vec3 minLighting = vec3(0.0);
    #endif

    // Lighting Tweaks
    #ifdef OVERWORLD
        ambientMult = vec3(mix(lightmapYM, pow2(lightmapYM) * lightmapYM, rainFactor));

        if (isEyeInWater != 1) {
            float dayFactor = lightmapY2 * (sunVisibility2 * 0.4 + (0.6 - 0.6 * pow2(invNoonFactor))) * (6.0 - 5.0 * rainFactor);
            dayFactor = max0(dayFactor - emission * 1000000.0);
            lightmapXM *= pow(max(lightmap.x, 0.001), dayFactor);

            shadowLighting *= 0.5 + 0.5 * lightmapYM;
        } else {
            lightmapXM *= 1.8;
            shadowLighting *= 0.25 + 0.75 * lightmapYM;
            minLighting *= 1.4;
        }
    #endif

    // Directional Shading
    float directionShade = 1.0;
    #ifdef DIRECTIONAL_SHADING
        if (!noDirectionalShading) {
            float NdotE = dot(normalM, eastVec);
            float absNdotE = abs(NdotE);
            float absNdotE2 = pow2(absNdotE);

            #if !defined NETHER || MC_VERSION < 11600
                float NdotUM = 0.75 + NdotU * 0.25;
            #else
                float NdotUM = 0.75 + max(NdotU, 0.0) * 0.25;
            #endif
            float NdotNM = 1.0 + 0.075 * absNdotN;
            float NdotEM = 1.0 - 0.1 * absNdotE2;
            directionShade = NdotUM * NdotEM * NdotNM;

            ambientMult *= mix(1.0, NdotEM, sunVisibility2);
            shadowLighting *= 1.0 + absNdotE2 * 0.75;

            #if defined PERPENDICULAR_TWEAKS && defined SIDE_SHADOWING
                ambientMult = mix(ambientMult,
                                (shadowLighting * 0.2 * pow(lightmapYM, 128.0) + ambientMult * ambientColor) / max(ambientColor, 0.001),
                                absNdotE2 * noonFactor20);
                if (subsurfaceMode == 0) shadowLighting *= 1.0 + pow2(absNdotN) * noonFactor20;
                else shadowLighting *= 1.0 - absNdotE2 * (0.35 * noonFactor20);
            #endif
        }
    #endif

    // Combine Lighting
    vec3 blockLighting = lightmapXM * blocklightCol;
    vec3 sceneLighting = shadowLighting * shadowMult + ambientColor * ambientMult;
    float dotSceneLighting = dot(sceneLighting, sceneLighting);
    
    // Vanilla Ambient Occlusion
    float vanillaAO = 1.0;
    if (subsurfaceMode != 0) vanillaAO = min1(glColor.a * 1.15);
    else if (!noVanillaAO) {
        vanillaAO = pow(glColor.a, 0.7
        + 0.06 * dotSceneLighting);
    }

    // Night Vision
    vec3 nightVisionLighting = nightVision * vec3(0.5, 0.5, 0.75);

    // Light Highlight
    vec3 lightHighlight = vec3(0.0);
    #ifdef LIGHT_HIGHLIGHT
        float specularHighlight = GGX(normalM, nViewPos, lightVec, NdotLmax0, smoothnessG);

        specularHighlight *= highlightMult;

        lightHighlight = isEyeInWater != 1 ? shadowMult : pow(shadowMult, vec3(0.25)) * 0.35;
        lightHighlight *= (subsurfaceHighlight + specularHighlight) * highlightColor;
    #endif

    // Final Lighting
    color.rgb *= directionShade * vanillaAO * (blockLighting + sceneLighting + minLighting + nightVisionLighting) + emission;
    color.rgb += lightHighlight;
    
    // Darkness Pulse
    color.rgb *= pow2(1.0 - darknessLightFactor);
}