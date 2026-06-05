#ifndef SKADI_ERRNO_H
#define SKADI_ERRNO_H

#ifndef __ASSEMBLER__
/* only relevant for C code */

#include <errno.h>
/** 
 * TODO Skadi subsystems cannot use errno directly due to TLS relocations
 * Instead, they import z_errno, a function that provides access via the subsystem call interface
 */
#ifdef errno
#undef errno
#endif /* errno */
extern int *z_errno(void);
#define errno (*z_errno())

#endif /* __ASSEMBLER__ */

#endif /* SKADI_ERRNO_H*/
