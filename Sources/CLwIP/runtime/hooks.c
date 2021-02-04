#include "hooks.h"

lwip_hook_ip4_route_src_t lwip_hook_ip4_route_src;

void lwip_set_hook_ip4_route_src(lwip_hook_ip4_route_src_t hook) {
    lwip_hook_ip4_route_src = hook;
}

lwip_hook_ip4_input_t lwip_hook_ip4_input;

void lwip_set_hook_ip4_input(lwip_hook_ip4_input_t hook) {
    lwip_hook_ip4_input = hook;
}
