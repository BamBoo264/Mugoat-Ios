#pragma once
#include <math.h>

static inline double pg_nova_vehicle_blend_duration(double packetInterval) {
  return fmax(80.0, fmin(180.0, packetInterval));
}

static inline void pg_nova_vehicle_blend(float pose[4], const float from[4],
                                         const float target[4], double elapsed, double duration) {
  float alpha = (float)fmax(0.0, fmin(1.0, elapsed / duration));
  for (int axis = 0; axis < 3; ++axis) {
    pose[axis] = from[axis] + (target[axis] - from[axis]) * alpha;
  }
  float turn = remainderf(target[3] - from[3], 360.0f);
  pose[3] = from[3] + turn * alpha;
}
