#include <stddef.h>

int __attribute__((weak)) compute_resource_attr_init_v2(void * attr, unsigned int size, unsigned int version) {
    (void)attr; (void)size; (void)version;
    return 0x80000404;
}
