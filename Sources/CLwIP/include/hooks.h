#ifndef HOOKS_H
#define HOOKS_H
#include "lwip/ip.h"

typedef struct netif *(*lwip_hook_ip4_route_src_t)(const ip4_addr_t *src, const ip4_addr_t *dest);

extern lwip_hook_ip4_route_src_t lwip_hook_ip4_route_src;
void lwip_set_hook_ip4_route_src(lwip_hook_ip4_route_src_t hook);


typedef int (*lwip_hook_ip4_input_t)(struct pbuf *pbuf, struct netif *input_netif);
extern lwip_hook_ip4_input_t lwip_hook_ip4_input;
void lwip_set_hook_ip4_input(lwip_hook_ip4_input_t hook);



#endif /* HOOKS_H */
