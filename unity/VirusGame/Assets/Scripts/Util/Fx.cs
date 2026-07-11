using UnityEngine;

namespace Virus.Util
{
    // Процедурные эффекты без ассетов: восходящие «мотыльки данных»,
    // вихрь зоны выноса, отражения неона (ReflectionProbe вместо SSR).
    public static class Fx
    {
        static Material _particleMat;
        static Material ParticleMat
        {
            get
            {
                if (_particleMat == null)
                {
                    _particleMat = Resources.Load<Material>("mat_particles");
                    if (_particleMat == null)
                    {
                        var sh = Shader.Find("Universal Render Pipeline/Particles/Unlit")
                              ?? Shader.Find("Particles/Standard Unlit");
                        if (sh != null) _particleMat = new Material(sh);
                    }
                }
                return _particleMat;
            }
        }

        // восходящие светлячки данных в объёме (атмосфера зала/Грида)
        public static ParticleSystem DataMotes(Transform parent, Vector3 center, Vector3 area,
                                               Color col, float rate)
        {
            var go = new GameObject("fx_motes");
            go.transform.SetParent(parent, false);
            go.transform.localPosition = center;
            var ps = go.AddComponent<ParticleSystem>();
            var main = ps.main;
            main.startColor = new Color(col.r, col.g, col.b, 0.55f);
            main.startSize = 0.09f;
            main.startSpeed = 0.55f;
            main.startLifetime = 7f;
            main.maxParticles = 400;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            var em = ps.emission;
            em.rateOverTime = rate * 0.7f;
            var sh = ps.shape;
            sh.shapeType = ParticleSystemShapeType.Box;
            sh.scale = area;
            var rend = go.GetComponent<ParticleSystemRenderer>();
            if (rend != null && ParticleMat != null) rend.sharedMaterial = ParticleMat;
            return ps;
        }

        // вихрь над зоной выноса: конус вверх
        public static ParticleSystem PortalSwirl(Transform parent, Vector3 pos, Color col)
        {
            var go = new GameObject("fx_portal");
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = Quaternion.Euler(-90, 0, 0);   // конус вверх
            var ps = go.AddComponent<ParticleSystem>();
            var main = ps.main;
            main.startColor = new Color(col.r, col.g, col.b, 0.85f);
            main.startSize = 0.12f;
            main.startSpeed = 2.6f;
            main.startLifetime = 1.6f;
            main.maxParticles = 300;
            var em = ps.emission;
            em.rateOverTime = 70f;
            var sh = ps.shape;
            sh.shapeType = ParticleSystemShapeType.Cone;
            sh.angle = 12f;
            sh.radius = 1.6f;
            var rend = go.GetComponent<ParticleSystemRenderer>();
            if (rend != null && ParticleMat != null) rend.sharedMaterial = ParticleMat;
            return ps;
        }

        // отражения в реальном времени: неон бликует на металле/плитке
        public static void ReflectionProbe(Transform parent, Vector3 center, Vector3 size)
        {
            var go = new GameObject("fx_probe");
            go.transform.SetParent(parent, false);
            go.transform.localPosition = center;
            var probe = go.AddComponent<ReflectionProbe>();
            probe.mode = UnityEngine.Rendering.ReflectionProbeMode.Realtime;
            probe.refreshMode = UnityEngine.Rendering.ReflectionProbeRefreshMode.OnAwake;
            probe.timeSlicingMode = UnityEngine.Rendering.ReflectionProbeTimeSlicingMode.IndividualFaces;
            probe.size = size;
            probe.resolution = 128;
            probe.boxProjection = true;
        }
    }
}
