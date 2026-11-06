#include "NovaVehicleBlend.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
  float start[4] = {0, 0, 0, 359};
  const float target[4] = {12, -6, 3, 1};
  float pose[4];
  pg_nova_vehicle_blend(pose, start, target, 50, 100);
  assert(pose[0] == 6 && pose[1] == -3 && pose[2] == 1.5f);
  assert(pose[3] == 360);
  pg_nova_vehicle_blend(pose, start, target, 200, 100);
  assert(pose[0] == 12 && pose[3] == 361);
  pg_nova_vehicle_blend(pose, start, target, -5, 100);
  assert(pose[0] == 0 && pose[3] == 359);
  assert(pg_nova_vehicle_blend_duration(15) == 80);
  assert(pg_nova_vehicle_blend_duration(110) == 110);
  assert(pg_nova_vehicle_blend_duration(400) == 180);
  puts("PASS: replica car interpolates position, crosses 360 degrees and clamps irregular updates");
}
