# Northcape Capability Operations Module

## Overview
This module implements the Northcape operations with the exception of subsystem calls via an MMIO interface.

## Operations

All operations are started when the user writes into the operations register.
All operations can be assumed to be completed (and any outputs are valid) when the highest bit in the operations register is set.
The register file is duplicated in a copy for the IRQ and a copy for the non-IRQ regimes. The non-IRQ copy occupies the lower 64 bytes of address space, while the IRQ copy occupies the higher 64 bytes of address space. The IRQ copy only supports the *inspect* operation.

Operations are not guaranteed to complete in bounded time except *inspect*.

### Create
In order to create capabilities, the user *first* specifies a source capability in the *Input* register.
The user can write the *Restriction* register to restrict the capability to a task on a device. Whether this register is interpreted is determined by the *restrict* bit in the *Operation* register.
*In a final write*, the user specifies the opcode, a length for the new segment and new permissions. The new segment starts *at the start or end of* the current segment, depending on the *direction* bit (0 for start, 1 for end).

### Derive
In order to derive ("create") indirect capabilities, the user *first* specifies a source capability in the *Input* register.
The user can write the *Restriction* register to restrict the capability to a task on a device. Whether this register is interpreted is determined by the *restrict* bit in the *Operation* register.
The user can write the *Aux 1* register to specify an offset into the parent capability's segment.
This defaults to 0.
*In a final write*, the user specifies the opcode, a length for the new segment and new permissions. The new segment starts at the offset indicated in Aux 1 or 0, respectively, from the beginning of the parent segment.

### Drop
In order to destroy ("drop") indirect capabilities, the user *first* specifies a source capability in the *Input* register.
*In a second write*, the user specifies the opcode for droop in the operations register. All other registers are ignored.
Drop requires a reference count of zero for the provided capability.
After completion, the given indirect capability cannot be used any more (any use results in a *bus fault*), and the parent capability's reference count is reduced by one.
The user device *needs to perform a read transaction on the output register*, despite there not being any output, before the operations module can accept the next transaction.

### Merge
In order to increase the size and permissions of direct capabilities, two *immediately* adjacent capabilities can be merged.
This is especially intended for the allocator.
To this end, the user *first* specifies the *left* input capability (with the *smaller* base address) in the *Input* register.
The user *second* specifies the *right* input capability (with the *larger* base address) in the *Aux 1* register.
The user can write the *Restriction* register to restrict the capability to a task on a device. Whether this register is interpreted is determined by the *restrict* bit in the *Operation* register.
*In a final write*, the user specifies the opcode and new permissions.
For merge, the permissions can be *looser* than those of the original capabilities.

### Clone
Clone is a synonym for *derive* with parent offset 0 and a segment length that equals the parent.

### Revoke
In order to re-claim storage in the memory allocator in exceptional circumstances (e.g., a task crashing), *revoke* can be used to create a new capability for a segment. The operation can restore permissions for the segment as well.
Data in the physical buffer is overwritten.
This operation is only valid for *direct capabilities*.
The user *first* specifies the input capability in the *Input* register.
The user can write the *Restriction* register to restrict the capability to a task on a device. Whether this register is interpreted is determined by the *restrict* bit in the *Operation* register.
*In a final write*, the user specifies the opcode and new permissions.

### Lock
Lock is the same operation as *clone*, but it returns a *lock holder* capability that grants *exclusive access* to the (part of the) physical segment that the input capability refers to.

### Inspect
Inspect can be used to read metadata associated with a capability token.
It will resolve the given capability token recursively and output metadata such as effective base and lenght, restrictions, permissions etc., filling in metadata from the parents as needed.
In case the (grandparent of the) capability is locked and the provided capability token does not belong to the lock-holder, an error is returned.
In case the capability to inspect has a *task-id-bound* restriction with a task or device ID *different* from the requester, an error is returned.
In case the capability to inspect has a *task-id-set* restriction with a task or device ID *different* from the requester, only the restrictions and the *execute* and *IRQ accessible* permissions are returned.
Otherwise (task-id-set/task-id-bound restriction with *same* task and device identifier or unrestricted), all metadata are returned.

### Restrict Access
The *restrict_access* operation can be used to modify a capability in-place.
As the name suggests, the operation can only make a capability *more* restrictive:
- It can remove (but not add) permissions. If permissions are indicated that are not set in the capability, this does *not* cause an error - instead, the operation module keeps the original value (unset). This can be used to keep permissions at their currently value - simply select them as set if you do not want them to be changed.
- It can add restrictions *if none are currently in effect*.
- *For indirect capabilities*, it can *decrease* the length and *increase* the offset as long as the bounds of the new access remain within the bounds of the access originally allowed. You need to account for an added offset in the subtracted length.
In order to use the operation, the user can specify an input capability in the input capability register, (optionally) a new restriction in the restriction register, an *addend* to the offset in the auxiliary register and a *subtrahend* for the length in the control register.
The corresponding opcode need to be indicated in the control register.
The user device *needs to perform a read transaction on the output register*, despite there not being any output, before the operations module can accept the next transaction.


### Sweep
Cleans up orphaned indirect capabilities in the CMT, which can be left, e.g., by *revoke*.


## Restriction Types
- 0x0: none
- 0x1: device-interpreted
- 0x2: task ID bound
- 0x3: set task ID

# Capability Type Codes
- 0x0: 32 bit offset
- 0x1: 0 bit offset
- 0x2: 16 bit offset
- 0x3: 24 bit offset

## Memory map - Restrictions
This applies to all operations that accept the "restrict" bit.
| Register | Bit  | Reg. Name  | Interpretation                           | R or W|
|----------|------|------------|------------------------------------------|-------|
|   0x10   | 63-48| Restriction| (task ID bound / set task id) Reserved   |   -   |
|   0x10   | 47-32| Restriction| (task ID bound / set task id) Device ID  |   W   |
|   0x10   | 31-0 | Restriction| (task ID bound / set task id) Task ID    |   W   |
|   0x10   | 63-0 | Restriction| (device-interpreted) Task ID             |   W   |
|   0x18   | 47-45| Operation  | Restriction type                         |   W   |

## Memory map - Control/Status
This applies to the *status* register with offset 0x28 across all operations.
Note that this register is duplicated into the ISR set, but the *Count* field read as 0 and writes are ignored.

| Register | Bit  | Reg. Name  | Interpretation                           | R or W|
|----------|------|------------|------------------------------------------|-------|
|   0x28   | 63   | Active     | Northcape is active and initialized      |   R   |
|   0x28   | 62-0 | Count      | Count of active capabilities in the CMT  |   R   |
|   0x28   | 63   | Activate   | Write-once reg that enables Northcape    |   W   |
|   0x28   | 62-0 | -          | Reserved: other control knobs            |   W   |

## Memory map - Create
| Register | Bit  | Reg. Name  | Interpretation   | R or W|
|----------|------|------------|------------------|-------|
|   0x0    | 63-0 | Input      | Input Cap. token |   W   |
|   0x8    | 63-0 | Output     | Output C.  token |   R   |
|   0x10   | 63-0 | Restriction| see Restr. map   |   W   |
|   0x18   | 63   | Operation  | Complete         |   R   |
|   0x18   | 62   | Operation  | In Progress      |   R   |
|   0x18   | 61   | Operation  | Error            |   R   |
|   0x18   | 60-0 | Operation  | Reserved         |   -   |
|   0x18   | 63-51| Operation  | Reserved         |   W   |
|   0x18   | 50   | Operation  | Cacheable TLB    |   W   |
|   0x18   | 49   | Operation  | Cacheable Access |   W   |
|   0x18   | 48-46| Operation  | Restriction type |   W   |
|   0x18   | 45-44| Operation  | Intended C. type |   W   |
|   0x18   | 43   | Operation  | direction        |   W   |
|   0x18   | 42-11| Operation  | New C. Length    |   W   |
|   0x18   | 10   | Operation  | restrict         |   W   |
|   0x18   | 9    | Operation  | Read Permission  |   W   |
|   0x18   | 8    | Operation  | Write Permission |   W   |
|   0x18   | 7    | Operation  | X Permission     |   W   |
|   0x18   | 6    | Operation  | Lockable perm.   |   W   |
|   0x18   | 5    | Operation  | IRQ access. perm |   W   |
|   0x18   | 4-0  | Operation  | Opcode = 0x0     |   W   |
|   0x20   | 63-0 | Aux 1      | Reserved         |   W   |
|   0x28   | 63-0 | Count      | Active Cap. Cnt  |   R   |
|   0x30   | 63-0 | TRNG       | 64 random bits   |   R   |

## Memory map - Derive
| Register | Bit  | Reg. Name  | Interpretation   | R or W|
|----------|------|------------|------------------|-------|
|   0x0    | 63-0 | Input      | Input Cap. token |   W   |
|   0x8    | 63-0 | Output     | Output C.  token |   R   |
|   0x10   | 63-0 | Restriction| see Restr. map   |   W   |
|   0x18   | 63   | Operation  | Complete         |   R   |
|   0x18   | 62   | Operation  | In Progress      |   R   |
|   0x18   | 61   | Operation  | Error            |   R   |
|   0x18   | 60-0 | Operation  | Reserved         |   -   |
|   0x18   | 63-51| Operation  | Reserved         |   W   |
|   0x18   | 50   | Operation  | Cacheable TLB    |   W   |
|   0x18   | 49   | Operation  | Cacheable Access |   W   |
|   0x18   | 48-46| Operation  | Restriction type |   W   |
|   0x18   | 45-44| Operation  | Intended C. type |   W   |
|   0x18   | 43   | Operation  | Reserved         |   -   |
|   0x18   | 42-11| Operation  | Derived C. Len   |   W   |
|   0x18   | 10   | Operation  | restrict         |   W   |
|   0x18   | 9    | Operation  | Read Permission  |   W   |
|   0x18   | 8    | Operation  | Write Permission |   W   |
|   0x18   | 7    | Operation  | X Permission     |   W   |
|   0x18   | 6    | Operation  | Reserved         |   -   |
|   0x18   | 5    | Operation  | IRQ access. perm |   W   |
|   0x18   | 4-0  | Operation  | Opcode = 0x1     |   W   |
|   0x20   | 63-32| Aux 1      | Reserved         |   W   |
|   0x20   | 31-0 | Aux 1      | Parent Offset    |   W   |
|   0x28   | 63-0 | Count      | Active Cap. Cnt  |   R   |
|   0x30   | 63-0 | TRNG       | 64 random bits   |   R   |

## Memory map - Drop
| Register | Bit  | Reg. Name  | Interpretation   | R or W|
|----------|------|------------|------------------|-------|
|   0x0    | 63-0 | Input      | Input Cap. token |   W   |
|   0x8    | 63-0 | Output     | Reserved         |   R   |
|   0x10   | 63-0 | Restriction| Reserved         |   -   |
|   0x18   | 63   | Operation  | Complete         |   R   |
|   0x18   | 62   | Operation  | In Progress      |   R   |
|   0x18   | 61   | Operation  | Error            |   R   |
|   0x18   | 60-0 | Operation  | Reserved         |   -   |
|   0x18   | 63-4 | Operation  | Reserved         |   -   |
|   0x18   | 4-0  | Operation  | Opcode = 0x2     |   W   |
|   0x20   | 63-0 | Aux 1      | Reserved         |   W   |
|   0x28   | 63-0 | Count      | Active Cap. Cnt  |   R   |
|   0x30   | 63-0 | TRNG       | 64 random bits   |   R   |

## Memory map - Merge
| Register | Bit  | Reg. Name  | Interpretation   | R or W|
|----------|------|------------|------------------|-------|
|   0x0    | 63-0 | Input      | Input left Cap.  |   W   |
|   0x8    | 63-0 | Output     | Output C.  token |   R   |
|   0x10   | 63-0 | Restriction| see Restr. map   |   W   |
|   0x18   | 63   | Operation  | Complete         |   R   |
|   0x18   | 62   | Operation  | In Progress      |   R   |
|   0x18   | 61   | Operation  | Error            |   R   |
|   0x18   | 60-0 | Operation  | Reserved         |   -   |
|   0x18   | 63-51| Operation  | Reserved         |   W   |
|   0x18   | 50   | Operation  | Cacheable TLB    |   W   |
|   0x18   | 49   | Operation  | Cacheable Access |   W   |
|   0x18   | 48-46| Operation  | Restriction type |   W   |
|   0x18   | 45-44| Operation  | Intended C. type |   W   |
|   0x18   | 43   | Operation  | Reserved         |   -   |
|   0x18   | 42-11| Operation  | Reserved         |   -   |
|   0x18   | 10   | Operation  | restrict         |   W   |
|   0x18   | 9    | Operation  | Read Permission  |   W   |
|   0x18   | 8    | Operation  | Write Permission |   W   |
|   0x18   | 7    | Operation  | X Permission     |   W   |
|   0x18   | 6    | Operation  | Lockable perm.   |   W   |
|   0x18   | 5    | Operation  | IRQ access. perm |   W   |
|   0x18   | 4-0  | Operation  | Opcode = 0x3     |   W   |
|   0x20   | 63-0 | Aux 1      | Input right Cap. |   W   |
|   0x28   | 63-0 | Count      | Active Cap. Cnt  |   R   |
|   0x30   | 63-0 | TRNG       | 64 random bits   |   R   |

## Memory map - Clone
| Register | Bit  | Reg. Name  | Interpretation   | R or W|
|----------|------|------------|------------------|-------|
|   0x0    | 63-0 | Input      | Input Cap. token |   W   |
|   0x8    | 63-0 | Output     | Output C.  token |   R   |
|   0x10   | 63-0 | Restriction| see Restr. map   |   W   |
|   0x18   | 63   | Operation  | Complete         |   R   |
|   0x18   | 62   | Operation  | In Progress      |   R   |
|   0x18   | 61   | Operation  | Error            |   R   |
|   0x18   | 60-0 | Operation  | Reserved         |   -   |
|   0x18   | 63-51| Operation  | Reserved         |   W   |
|   0x18   | 50   | Operation  | Cacheable TLB    |   W   |
|   0x18   | 49   | Operation  | Cacheable Access |   W   |
|   0x18   | 48-46| Operation  | Restriction type |   W   |
|   0x18   | 45-44| Operation  | Intended C. type |   W   |
|   0x18   | 43   | Operation  | Reserved         |   -   |
|   0x18   | 42-11| Operation  | Reserved         |   -   |
|   0x18   | 10   | Operation  | restrict         |   W   |
|   0x18   | 9    | Operation  | Read Permission  |   W   |
|   0x18   | 8    | Operation  | Write Permission |   W   |
|   0x18   | 7    | Operation  | X Permission     |   W   |
|   0x18   | 6    | Operation  | Reserved         |   -   |
|   0x18   | 5    | Operation  | IRQ access. perm |   W   |
|   0x18   | 4-0  | Operation  | Opcode = 0x4     |   W   |
|   0x20   | 63-0 | Aux 1      | Reserved         |   -   |
|   0x28   | 63-0 | Count      | Active Cap. Cnt  |   R   |
|   0x30   | 63-0 | TRNG       | 64 random bits   |   R   |

## Memory map - Revoke
| Register | Bit  | Reg. Name  | Interpretation   | R or W|
|----------|------|------------|------------------|-------|
|   0x0    | 63-0 | Input      | Input Cap. token |   W   |
|   0x8    | 63-0 | Output     | Output C.  token |   R   |
|   0x10   | 63-0 | Restriction| see Restr. map   |   W   |
|   0x18   | 63   | Operation  | Complete         |   R   |
|   0x18   | 62   | Operation  | In Progress      |   R   |
|   0x18   | 61   | Operation  | Error            |   R   |
|   0x18   | 60-0 | Operation  | Reserved         |   -   |
|   0x18   | 63-51| Operation  | Reserved         |   W   |
|   0x18   | 50   | Operation  | Cacheable TLB    |   W   |
|   0x18   | 49   | Operation  | Cacheable Access |   W   |
|   0x18   | 48-46| Operation  | Restriction type |   W   |
|   0x18   | 45-44| Operation  | Intended C. type |   W   |
|   0x18   | 43   | Operation  | Reserved         |   -   |
|   0x18   | 42-11| Operation  | Reserved         |   -   |
|   0x18   | 10   | Operation  | restrict         |   W   |
|   0x18   | 9    | Operation  | Read Permission  |   W   |
|   0x18   | 8    | Operation  | Write Permission |   W   |
|   0x18   | 7    | Operation  | X Permission     |   W   |
|   0x18   | 6    | Operation  | Lockable perm.   |   W   |
|   0x18   | 5    | Operation  | IRQ access. perm |   W   |
|   0x18   | 4-0  | Operation  | Opcode = 0x5     |   W   |
|   0x20   | 63-0 | Aux 1      | Reserved         |   W   |
|   0x28   | 63-0 | Count      | Active Cap. Cnt  |   R   |
|   0x30   | 63-0 | TRNG       | 64 random bits   |   R   |

## Memory map - Lock
| Register | Bit  | Reg. Name  | Interpretation   | R or W|
|----------|------|------------|------------------|-------|
|   0x0    | 63-0 | Input      | Input Cap. token |   W   |
|   0x8    | 63-0 | Output     | Output C.  token |   R   |
|   0x10   | 63-0 | Restriction| see Restr. map   |   W   |
|   0x18   | 63   | Operation  | Complete         |   R   |
|   0x18   | 62   | Operation  | In Progress      |   R   |
|   0x18   | 61   | Operation  | Error            |   R   |
|   0x18   | 60-0 | Operation  | Reserved         |   -   |
|   0x18   | 63-51| Operation  | Reserved         |   W   |
|   0x18   | 50   | Operation  | Cacheable TLB    |   W   |
|   0x18   | 49   | Operation  | Cacheable Access |   W   |
|   0x18   | 48-46| Operation  | Restriction type |   W   |
|   0x18   | 45-44| Operation  | Intended C. type |   W   |
|   0x18   | 43   | Operation  | Reserved         |   -   |
|   0x18   | 42-11| Operation  | Reserved         |   -   |
|   0x18   | 10   | Operation  | restrict         |   W   |
|   0x18   | 9    | Operation  | Read Permission  |   W   |
|   0x18   | 8    | Operation  | Write Permission |   W   |
|   0x18   | 7    | Operation  | X Permission     |   W   |
|   0x18   | 6    | Operation  | Reserved         |   -   |
|   0x18   | 5    | Operation  | IRQ access. perm |   W   |
|   0x18   | 4-0  | Operation  | Opcode = 0x6     |   W   |
|   0x20   | 63-0 | Aux 1      | Reserved         |   -   |
|   0x28   | 63-0 | Count      | Active Cap. Cnt  |   R   |
|   0x30   | 63-0 | TRNG       | 64 random bits   |   R   |


## Memory map - Inspect
| Register | Bit  | Reg. Name  | Interpretation   | R or W|
|----------|------|------------|------------------|-------|
|   0x0    | 63-0 | Input      | Input Cap. token |   W   |
|   0x8    | 63-0 | Output     | Reserved         |   -   |
|   0x10   | 63-0 | Restriction| see Restr. map   |   R   |
|   0x18   | 63   | Operation  | Complete         |   R   |
|   0x18   | 62   | Operation  | In Progress      |   R   |
|   0x18   | 61   | Operation  | Error            |   R   |
|   0x18   | 60-48| Operation  | Reserved         |   R   |
|   0x18   | 63-49| Operation  | Reserved         |   W   |
|   0x18   | 48-46| Operation  | Restriction type |   R   |
|   0x18   | 45-44| Operation  | Reserved         |   -   |
|   0x18   | 43   | Operation  | Reserved         |   -   |
|   0x18   | 42-11| Operation  | C. Length        |   R   |
|   0x18   | 10   | Operation  | Reserved         |   R   |
|   0x18   | 9    | Operation  | Read Permission  |   R   |
|   0x18   | 8    | Operation  | Write Permission |   R   |
|   0x18   | 7    | Operation  | X Permission     |   R   |
|   0x18   | 6    | Operation  | Lockable perm.   |   R   |
|   0x18   | 5    | Operation  | IRQ access. perm |   R   |
|   0x18   | 4-0  | Operation  | Opcode = 0x7     |   W   |
|   0x20   | 63-48| Aux 1      | Reserved         |   R   |
|   0x20   | 47-32| Aux 1      | Reference count  |   R   |
|   0x20   | 31-0 | Aux 1      | C. Base          |   R   |
|   0x28   | 63-0 | Count      | Active Cap. Cnt  |   R   |
|   0x30   | 63-0 | TRNG       | 64 random bits   |   R   |

## Memory map - Restrict Access
| Register | Bit  | Reg. Name  | Interpretation   | R or W|
|----------|------|------------|------------------|-------|
|   0x0    | 63-0 | Input      | Input Cap. token |   W   |
|   0x8    | 63-0 | Output     | Reserved         |   R   |
|   0x10   | 63-0 | Restriction| see Restr. map   |   W   |
|   0x18   | 63   | Operation  | Complete         |   R   |
|   0x18   | 62   | Operation  | In Progress      |   R   |
|   0x18   | 61   | Operation  | Error            |   R   |
|   0x18   | 60-0 | Operation  | Reserved         |   -   |
|   0x18   | 63-51| Operation  | Reserved         |   W   |
|   0x18   | 50   | Operation  | Cacheable TLB    |   W   |
|   0x18   | 49   | Operation  | Cacheable Access |   W   |
|   0x18   | 48-46| Operation  | Restriction type |   W   |
|   0x18   | 45-44| Operation  | Reserved         |   -   |
|   0x18   | 43   | Operation  | -                |   -   |
|   0x18   | 42-11| Operation  | C. Length subtr. |   W   |
|   0x18   | 10   | Operation  | restrict         |   W   |
|   0x18   | 9    | Operation  | Read Permission  |   W   |
|   0x18   | 8    | Operation  | Write Permission |   W   |
|   0x18   | 7    | Operation  | X Permission     |   W   |
|   0x18   | 6    | Operation  | Lockable perm.   |   W   |
|   0x18   | 5    | Operation  | IRQ access. perm |   W   |
|   0x18   | 4-0  | Operation  | Opcode = 0x8     |   W   |
|   0x20   | 63-32| Aux 1      | Reserved         |   R   |
|   0x20   | 31-0 | Aux 1      | C. Base Addend   |   R   |
|   0x28   | 63-0 | Count      | Active Cap. Cnt  |   R   |
|   0x30   | 63-0 | TRNG       | 64 random bits   |   R   |

## Memory map - Sweep
| Register | Bit  | Reg. Name  | Interpretation   | R or W|
|----------|------|------------|------------------|-------|
|   0x0    | 63-0 | Input      | Reserved         |   -   |
|   0x8    | 63-0 | Output     | Reserved         |   -   |
|   0x10   | 63-0 | Restriction| Reserved         |   -   |
|   0x18   | 63   | Operation  | Complete         |   R   |
|   0x18   | 62   | Operation  | In Progress      |   R   |
|   0x18   | 61   | Operation  | Error            |   R   |
|   0x18   | 60-0 | Operation  | Reserved         |   -   |
|   0x18   | 63-4 | Operation  | Reserved         |   W   |
|   0x18   | 63-5 | Operation  | Reserved         |   W   |
|   0x18   | 4-0  | Operation  | Opcode = 0xb     |   W   |
|   0x20   | 63-0 | Aux 1      | Reserved         |   R   |
