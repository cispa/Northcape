/**
  * Datatypes and constants used throughout the Northcape system.
  */
package northcape_types;

  import axi5::axi_size_t;

  localparam NORTHCAPE_CAPABILITY_ID_WIDTH = 38;
  localparam NORTHCAPE_CAPABILITY_OFFSET_WIDTH = 32;
  localparam NORTHCAPE_CAPABILITY_TAG_WIDTH = 16;
  localparam NORTHCAPE_TOKEN_WIDTH = 64;
  localparam NORTHCAPE_TOKEN_TYPE_WIDTH = 2;
  localparam NORTHCAPE_TOKEN_NON_ID_OFFSET_WIDTH = NORTHCAPE_TOKEN_WIDTH - NORTHCAPE_TOKEN_TYPE_WIDTH - NORTHCAPE_CAPABILITY_TAG_WIDTH;

  localparam NORTHCAPE_LOCK_KEY_WIDTH = 32;

  // types for MAXIMUM size of the respective components
  typedef enum bit [1:0] {
    OFFSET_32_BIT = 2'b00,
    OFFSET_8_BIT  = 2'b01,
    OFFSET_16_BIT = 2'b10,
    OFFSET_24_BIT = 2'b11
  } capability_type_t;
  typedef logic [NORTHCAPE_CAPABILITY_TAG_WIDTH-1:0] capability_tag_t;
  typedef logic [NORTHCAPE_CAPABILITY_ID_WIDTH-1:0] capability_id_t;
  typedef logic [NORTHCAPE_CAPABILITY_OFFSET_WIDTH-1:0] capability_off_t;

  localparam capability_tag_t NORTHCAPE_ROOT_CAPABILITY_TAG = 0;
  localparam capability_id_t NORTHCAPE_ROOT_CAPABILITY_ID = 0;

  // assume 32 bit physical address space
  localparam AXIS_VALIDATE_BASE_WIDTH = 32;

  typedef logic [AXIS_VALIDATE_BASE_WIDTH-1:0] segment_base_addr_t;

  // segments are <= 2^32 bytes
  localparam AXIS_VALIDATE_LENGTH_WIDTH = 32;

  typedef logic [AXIS_VALIDATE_LENGTH_WIDTH-1:0] segment_length_t;

  // tdata needs to be multiple of 8 bits
  // READ_WRITE needed for atomic accesses
  // ACCESS_NONE is used for leaf capability in ops: no PERMISSIONS checked, but other metadata like tag and restrictions
  // ACCESS_DERIVE_RECURSION is used for parent/grandparent capabilities in resolver and ops: no PERMISSIONS and no RESTRICTIONS checked (might not match!), but tag and (resolver) bounds
  typedef enum logic [7:0] {
    ACCESS_NONE,
    ACCESS_DERIVE_RECURSION,
    READ,
    WRITE,
    READ_WRITE,
    EXECUTE,
    READ_IRQ,
    WRITE_IRQ,
    READ_WRITE_IRQ,
    EXECUTE_IRQ,
    PERM_RESERVED
  } axis_validate_request_perm_t;

  localparam ATOMIC_MAX_ID_LEN = 32;
  localparam ATOMIC_MAX_USER_LEN = 64;

  // used between channels of MMU to inform read that an atomic transaction needs to be forwarded
  typedef struct {
    logic atomic_transaction_requested;

    axi5::axi_burst_t burst_type;
    // capability token used for mask/offset calculations for narrow bursts
    logic [63:0] slave_token;
    segment_base_addr_t segment_start;
    segment_base_addr_t segment_end;
    axi_size_t transaction_size;

    // we have fallen into an error state - need to give all-zeros read response
    logic atomic_error;
    axi5::axi_len_t atomic_request_len;
    bit [ATOMIC_MAX_ID_LEN-1:0] atomic_request_id;

  } atomic_transaction_request_t;

  localparam capability_id_t NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_32 = 2**(NORTHCAPE_TOKEN_NON_ID_OFFSET_WIDTH - 32) - 1;
  localparam capability_id_t NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_24 = 2**(NORTHCAPE_TOKEN_NON_ID_OFFSET_WIDTH - 24) - 1;
  localparam capability_id_t NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_16 = 2**(NORTHCAPE_TOKEN_NON_ID_OFFSET_WIDTH - 16) - 1;
  localparam capability_id_t NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_8 = '1;

  function automatic segment_length_t max_length_for_capability_type(
      input capability_type_t capability_type);
    // due to the encoding of the type, we can technically have a length of up to 2**32-1 bytes for OFFSET_32
    // the other offsets do NOT have this implicit -1
    unique case (capability_type)
      OFFSET_32_BIT: return '1;
      OFFSET_24_BIT: return 2 ** 24;
      OFFSET_16_BIT: return 2 ** 16;
      OFFSET_8_BIT: return 2 ** 8;
      default: return 0;
    endcase

  endfunction

  function automatic capability_id_t get_id_mask_for_capability_type(
      input capability_type_t capability_type);
    unique case (capability_type)
      OFFSET_32_BIT: return (2 ** 14) - 1;
      OFFSET_24_BIT: return (2 ** 22) - 1;
      OFFSET_16_BIT: return (2 ** 30 - 1);
      OFFSET_8_BIT: return (2 ** 38) - 1;
      default: return 0;
    endcase
  endfunction

  function capability_id_t get_max_capability_id(capability_type_t capability_type);
    unique case (capability_type)
      OFFSET_8_BIT: return NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_8;
      OFFSET_16_BIT: return NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_16;
      OFFSET_24_BIT: return NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_24;
      default: return NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_32;
    endcase
  endfunction

  // wrapper for generic functions
  class capability_accessors #(
      parameter int AXI_ADDR_WIDTH = 64
  );

    static function capability_type_t capability_get_type(
        input bit [AXI_ADDR_WIDTH - 1:0] capability_token);
      capability_type_t ret;
      logic [1:0] first_bits;
      first_bits = capability_token[AXI_ADDR_WIDTH-1:AXI_ADDR_WIDTH-2];
`ifdef ASIC
      unique case (first_bits)
        OFFSET_32_BIT: return OFFSET_32_BIT;
        OFFSET_8_BIT: return OFFSET_8_BIT;
        OFFSET_16_BIT: return OFFSET_16_BIT;
        default: return OFFSET_24_BIT;
      endcase
`else
      /* verilator lint_off CMPCONST */
      $cast(ret, first_bits);
      /* verilator lint_on CMPCONST */
`endif
      return ret;
    endfunction

    static function capability_tag_t capability_get_tag(
        input logic [AXI_ADDR_WIDTH - 1:0] capability_token);
      return capability_token[AXI_ADDR_WIDTH-3:AXI_ADDR_WIDTH-(2+NORTHCAPE_CAPABILITY_TAG_WIDTH)];
    endfunction

    static function capability_id_t capability_get_id(
        input logic [AXI_ADDR_WIDTH - 1:0] capability_token);
      capability_type_t cap_type = capability_get_type(capability_token);

      unique case (cap_type)
        OFFSET_32_BIT: begin
          return {24'h0, capability_token[AXI_ADDR_WIDTH-(2+NORTHCAPE_CAPABILITY_TAG_WIDTH+1):32]};
        end
        OFFSET_24_BIT: begin
          return {16'h0, capability_token[AXI_ADDR_WIDTH-(2+NORTHCAPE_CAPABILITY_TAG_WIDTH+1):24]};
        end
        OFFSET_16_BIT: begin
          return {8'h0, capability_token[AXI_ADDR_WIDTH-(2+NORTHCAPE_CAPABILITY_TAG_WIDTH+1):16]};
        end
        OFFSET_8_BIT: begin
          return capability_token[AXI_ADDR_WIDTH-(2+NORTHCAPE_CAPABILITY_TAG_WIDTH+1):8];
        end
        default: return '1;
      endcase
    endfunction

    static function capability_off_t capability_get_offset(
        input logic [AXI_ADDR_WIDTH - 1:0] capability_token);
      capability_type_t cap_type = capability_get_type(capability_token);
      unique case (cap_type)
        OFFSET_32_BIT: begin
          return capability_token[31:0];
        end
        OFFSET_24_BIT: begin
          return {8'h0, capability_token[23:0]};
        end
        OFFSET_16_BIT: begin
          return {16'h0, capability_token[15:0]};
        end
        OFFSET_8_BIT: begin
          return {24'h0, capability_token[7:0]};
        end
        default: return '1;
      endcase
    endfunction

    static function automatic bit [AXI_ADDR_WIDTH - 1:0] capability_set_type(
        input bit [AXI_ADDR_WIDTH - 1:0] capability_token, input capability_type_t new_type);
      bit [AXI_ADDR_WIDTH - 1:0] ret;
      ret = capability_token;
      ret[AXI_ADDR_WIDTH-1:AXI_ADDR_WIDTH-2] = new_type;
      return ret;
    endfunction

    static function bit [AXI_ADDR_WIDTH - 1:0] capability_set_tag(
        input logic [AXI_ADDR_WIDTH - 1:0] capability_token, input capability_tag_t new_tag);
      bit [AXI_ADDR_WIDTH - 1:0] ret;
      ret = capability_token;
      ret[AXI_ADDR_WIDTH-3:AXI_ADDR_WIDTH-(2+NORTHCAPE_CAPABILITY_TAG_WIDTH)] = new_tag;
      return ret;
    endfunction

    static function bit [AXI_ADDR_WIDTH - 1:0] capability_set_id(
        input logic [AXI_ADDR_WIDTH - 1:0] capability_token, input capability_id_t new_id);
      capability_type_t cap_type = capability_get_type(capability_token);
      bit [AXI_ADDR_WIDTH - 1:0] ret;
      ret = capability_token;

      unique case (cap_type)
        OFFSET_32_BIT: begin
          ret[AXI_ADDR_WIDTH-(2+NORTHCAPE_CAPABILITY_TAG_WIDTH+1):32] = new_id[NORTHCAPE_CAPABILITY_ID_WIDTH-24:0];
        end
        OFFSET_24_BIT: begin
          ret[AXI_ADDR_WIDTH-(2+NORTHCAPE_CAPABILITY_TAG_WIDTH+1):24] = new_id[NORTHCAPE_CAPABILITY_ID_WIDTH-16:0];
        end
        OFFSET_16_BIT: begin
          ret[AXI_ADDR_WIDTH-(2+NORTHCAPE_CAPABILITY_TAG_WIDTH+1):16] = new_id[NORTHCAPE_CAPABILITY_ID_WIDTH-8:0];
        end
        OFFSET_8_BIT: begin
          ret[AXI_ADDR_WIDTH-(2+NORTHCAPE_CAPABILITY_TAG_WIDTH+1):8] = new_id;
        end
        default: begin
          // nothing to do
        end
      endcase
      return ret;
    endfunction

    static function bit capability_set_offset(inout bit [AXI_ADDR_WIDTH - 1:0] capability_token,
                                              input capability_off_t new_offset);
      capability_type_t cap_type = capability_get_type(capability_token);
      unique case (cap_type)
        OFFSET_32_BIT: begin
          capability_token[31:0] = new_offset[31:0];
          return 1;
        end
        OFFSET_24_BIT: begin
          capability_token[23:0] = new_offset[23:0];
          return 1;
        end
        OFFSET_16_BIT: begin
          capability_token[15:0] = new_offset[15:0];
          return 1;
        end
        OFFSET_8_BIT: begin
          capability_token[7:0] = new_offset[7:0];
          return 1;
        end
        default: return 0;
      endcase
    endfunction


  endclass

  // wrapper for strobe/data mask functions
  class northcape_axi_masks #(
      parameter int MASK_TARGET_WIDTH_BITS = -1,
      parameter int AXI_DATA_WIDTH = -1
  );
    typedef logic [$clog2(AXI_DATA_WIDTH/8)-1:0] byte_in_burst_count_t;

    static function logic [AXI_DATA_WIDTH-1:0] stretchMask(
        input logic [AXI_DATA_WIDTH/8-1:0] bytewise_mask);
      logic [AXI_DATA_WIDTH/8 * 8-1:0] ret;

      for (int i = 0; i < AXI_DATA_WIDTH / 8; i = i + 1) begin
        ret[i*8+:8] = bytewise_mask[i] ? 8'hff : 8'h00;
      end

      return ret;
    endfunction
  endclass

  typedef enum logic [2:0] {
    NORTHCAPE_CMT_INVALID = 3'b000,
    NORTHCAPE_CMT_DIRECT = 3'b001,
    NORTHCAPE_CMT_INDIRECT = 3'b010,
    NORTHCAPE_CMT_LOCK_HOLDER = 3'b011,
    NORTHCAPE_CMT_PAGED_OUT = 3'b100,
    NORTHCAPE_CMT_REVOCATION = 3'b101
  } northcape_cmt_entry_type_t;

  typedef logic [31:0] northcape_physical_address_t;
  // these should be the same, as we want the two capabilities to have the same layout in memory
  typedef northcape_physical_address_t northcape_page_number_t;

  typedef logic [31:0] northcape_segment_length_t;

  typedef logic [63:0] northcape_parent_capability_t;

  typedef logic [15:0] northcape_reference_count_t;

  typedef logic [NORTHCAPE_LOCK_KEY_WIDTH-1:0] northcape_lock_key_t;

  /**
 * @brief Different interpretations of restriction bits
 * @value NORTHCAPE_RESTRICTIONS_NONE no restrictions, how ever holds capability can use it
 * @value NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED device-interpreted restrictions. 64 bits that are transparent to the cap. system.
 * @value NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND payload is struct norhcape_task_restriction_t and encodes which task(s) can use the capability.
 * @value NORTHCAPE_RESTRICTIONS_SET_TASK_ID Only allowed for X-only capabilities. Payload is struct northcape_task_restriction_t. When the X-only capability is executed, the task ID in the CPU is overwritten with the encoded one.
 */
  typedef enum logic [2:0] {
    NORTHCAPE_RESTRICTIONS_NONE = 3'b000,
    NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED = 3'b001,
    NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND = 3'b010,
    NORTHCAPE_RESTRICTIONS_SET_TASK_ID = 3'b011
  } northcape_restriction_type_t;

  localparam NORTHCAPE_TASK_ID_WIDTH = 32;
  typedef logic [NORTHCAPE_TASK_ID_WIDTH-1:0] task_id_t;
  typedef logic [15:0] device_id_t;

  // MMU devices always have two (implicit) devices: read and write chan
  // these should have subsequent IDs
  // thus, ignore last bit of device ID in comparison
  localparam device_id_t NORTHCAPE_DEVICE_ID_COMP_IGNORED_BITS = 1'b1;

  // sequence matters - create caps returns this verbatim!
  typedef struct packed {
    logic [15:0] reserved;  // TODO: additional restrictions like cannot be delegated etc.?
    device_id_t device_id;  // identifier of the device, hard-coded in MMU
    task_id_t task_id;
  } northcape_task_restriction_t;

  typedef logic [63:0] northcape_device_interpreted_restriction_t;

  typedef union packed {
    northcape_device_interpreted_restriction_t device_interpreted_bits;
    northcape_task_restriction_t task_restriction;
  } northcape_restriction_body_t;

  typedef struct packed {
    northcape_restriction_type_t restriction_type;
    northcape_restriction_body_t body;
  } northcape_restrictions_t;

  typedef logic [15:0] northcape_mac_tag_t;

  typedef logic [15:0] northcape_nonce_t;

  /**
 * Direct capability: resolves to physical address.
 */
  typedef struct packed {
    northcape_physical_address_t base;
    northcape_segment_length_t length;
    northcape_lock_key_t locked_key;  // 0 for not locked or the key encoded by the lock holder
    logic [NORTHCAPE_LOCK_KEY_WIDTH-1:0] lock_reserved;  // 32 bits, but accounted for 64
  } northcape_cmt_physical_location_t;
  /**
 * Indirect capability: resolves to physical address + parent (such that we can check if parent was revoked).
 */
  typedef struct packed {
    northcape_physical_address_t effective_base;
    northcape_segment_length_t length;
    northcape_parent_capability_t parent;
  } northcape_cmt_indirect_location_t;
  /**
 * Lock holder capability: resolves to direct or indirect capability + parent (such that we can check if key matches and parent still exists).
 */
  typedef struct packed {
    northcape_parent_capability_t parent;
    northcape_lock_key_t lock_key;  // lock key that we currently lock with
    northcape_lock_key_t prev_key;  // previous key - to be restored on unlock
  } northcape_cmt_lock_holder_location_t;

  /**
 * Paged-out capability: resolves to pagefile.
 */
  typedef struct packed {
    northcape_page_number_t pagefile_number;
    northcape_segment_length_t length;
    logic [63:0] padding;
  } northcape_cmt_pagefile_location_t;


  typedef union packed {
    northcape_cmt_physical_location_t physical_location;
    northcape_cmt_indirect_location_t indirect_location;
    northcape_cmt_lock_holder_location_t lock_holder_location;
    northcape_cmt_pagefile_location_t pagefile_location;
  } northcape_cmt_location_t;
  /**
 * Permissions allowed for direct capability.
 */
  typedef struct packed {
    logic read_permission;
    logic write_permission;
    logic execute_permission;
    logic lockable_permission;
    logic irq_accessible_permission;
    /* can be included in capability TLB, i.e., non-uniform access time permissible */
    logic cacheable_tlb;
    /* data/instructions can be cached */
    logic cacheable_access;
  } northcape_direct_capability_permissions_t;
  /**
 * Permissions allowed for other capability types.
 */
  typedef struct packed {
    logic read_permission;
    logic write_permission;
    logic execute_permission;
    logic [0:0] padding;
    logic irq_accessible_permission;
    /* can be included in capability TLB, i.e., non-uniform access time permissible */
    logic cacheable_tlb;
    /* data/instructions can be cached */
    logic cacheable_access;
  } northcape_indirect_capability_permissions_t;

  typedef union packed {
    northcape_direct_capability_permissions_t   direct_capability_permissions;
    northcape_indirect_capability_permissions_t indirect_capability_permissions;
  } northcape_permissions_t;

  typedef struct packed {
    northcape_cmt_entry_type_t capability_type;
    // union, depends on type
    northcape_cmt_location_t location;
    // not used for lock holder capability and paged out capability (must be 0), reference count for other capabilities
    northcape_reference_count_t refcount;
    // not used for paged-out capability; restrict the allowed users of the capability
    northcape_restrictions_t restrictions;
    // determine which type of access is attempted
    northcape_permissions_t permissions;
    // to prevent forgery of capabilities, conveyed in token
    northcape_mac_tag_t tag;
    // counter value that makes sure tag is changed when capability changes
    northcape_nonce_t nonce;
    // watermark for how many bits we can still distribute to the other fields if needed
    logic [2:0] reserved;
  } northcape_cmt_entry_t;

  function automatic string print_third_location_addr(const ref northcape_cmt_entry_t entry);
    unique case (entry.capability_type)
      NORTHCAPE_CMT_DIRECT:
      return $sformatf("lock key %x", entry.location.physical_location.locked_key);
      NORTHCAPE_CMT_INDIRECT:
      return $sformatf("parent %x", entry.location.indirect_location.parent);
      NORTHCAPE_CMT_LOCK_HOLDER:
      return $sformatf(
          "parent %x lock holder key %x previous key %x",
          entry.location.lock_holder_location.parent,
          entry.location.lock_holder_location.lock_key,
          entry.location.lock_holder_location.prev_key
      );
      default: return "";
    endcase
  endfunction

  function automatic string print_restriction(const ref northcape_restrictions_t restr);
    unique case (restr.restriction_type)
      NORTHCAPE_RESTRICTIONS_NONE: return "no restrictions";
      NORTHCAPE_RESTRICTIONS_SET_TASK_ID:
      return $sformatf(
          "task ID set restriction: task id %x device id %x",
          restr.body.task_restriction.task_id,
          restr.body.task_restriction.device_id
      );
      NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND:
      return $sformatf(
          "task ID bound restriction: task id %x device id %x",
          restr.body.task_restriction.task_id,
          restr.body.task_restriction.device_id
      );
      NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED:
      return $sformatf("device interpreted restrictions %x", restr.body.device_interpreted_bits);
      default: return "unknown";
    endcase
  endfunction
`ifndef ASIC
  function automatic string print_cmt_entry(const ref northcape_cmt_entry_t entry);
    return $sformatf(
        "Capability type %s base %x length %d %s refcount %d restrictions %s read perm %b write perm %b x perm %b lockable %b IRQ accessible %b tag %x nonce %x",
        entry.capability_type.name(),
        entry.location.physical_location.base,
        entry.location.physical_location.length,
        print_third_location_addr(
            entry
        ),
        entry.refcount,
        print_restriction(
            entry.restrictions
        ),
        entry.permissions.direct_capability_permissions.read_permission,
        entry.permissions.direct_capability_permissions.write_permission,
        entry.permissions.direct_capability_permissions.execute_permission,
        entry.permissions.direct_capability_permissions.lockable_permission,
        entry.permissions.direct_capability_permissions.irq_accessible_permission,
        entry.tag,
        entry.nonce
    );
  endfunction
`endif
  /**
  * Default values for root capability entry
  */
  localparam northcape_nonce_t NORTHCAPE_ROOT_CAPABILITY_NONCE = '0;
  localparam northcape_restriction_type_t NORTHCAPE_ROOT_CAPABILITY_RESTRICTION_TYPE = NORTHCAPE_RESTRICTIONS_NONE;
  localparam northcape_physical_address_t NORTHCAPE_ROOT_CAPABILITY_RESTRICTION_BASE = '0;
  localparam segment_length_t NORTHCAPE_ROOT_CAPABILITY_LENGTH = 32'hffffffff;

  /**
   * Default loader task
   * Special privilege: can create set-task-ID capabilities with different task ID
   */
  localparam device_id_t NORTHCAPE_LOADER_TASK_DEVICE_ID = '0;
  localparam task_id_t NORTHCAPE_LOADER_TASK_TASK_ID = '0;

  typedef struct packed {
    bit is_recursion;
    // for lock-holder, no immediate base/length information - need to take them from first non-resolver capability 
    bit have_base_length;
    // first lock key counts
    bit have_lock_key;
    bit [4:0] reserved;
  } axis_validate_request_flags_t;


  // careful - axis_validate_response_tdata_t must be divisable by 8 bits at the end!
  typedef enum logic [5:0] {
    NORTHCAPE_RESOLVE_NO_ERROR = 6'd0,
    NORTHCAPE_RESOLVE_ERROR_TAG = 6'd1,
    NORTHCAPE_RESOLVE_ERROR_PERMISSIONS = 6'd2,
    NORTHCAPE_RESOLVE_ERROR_RESTRICTIONS = 6'd3,
    NORTHCAPE_RESOLVE_ERROR_CAP_TYPE = 6'd4,
    NORTHCAPE_RESOLVE_ERROR_LOCKED = 6'd5,
    NORTHCAPE_RESOLVE_ERROR_BUS = 6'd6,
    NORTHCAPE_RESOLVE_ERROR_BOUNDS = 6'd7,
    NORTHCAPE_RESOLVE_ERROR_CMT_OVERLAP = 6'd8,
    NORTHCAPE_RESOLVE_ERROR_SUBSYS_CALL_OFFSET = 6'd9,
    NORTHCAPE_RESOLVE_ERROR_INVALID_SCALL_TARGET = 6'd10
  } northcape_resolve_error_t;


  // allowed bytes is returned in the response
  // the MMU does  not yet know whether a request is permissible
  // in case the last transfer attempts to R/W over the end of the segment and the segment is not buswidth-aligned, the MMU will only know whether the transfer is OK on the last beat
  typedef struct packed {
    capability_id_t address;
    capability_tag_t tag;
    axis_validate_request_perm_t access_type;
    device_id_t device_id;
    task_id_t task_id;

    axis_validate_request_flags_t flags;
    // when the capability resolver recurses, we need to convey the base address and length
    // of the original capability - we are only here to check whether the parent(s) still exist(s)
    segment_base_addr_t original_address;
    segment_length_t original_segment_length;
    // for the top capability, do permissions and task ID permit access?
    logic original_permission_tid_match;
    // lock key, collected from lock-holder
    northcape_lock_key_t lock_key;
    // permissions from the original capability
    northcape_permissions_t original_permissions;

    // restriction response for recursion
    northcape_restriction_body_t restriction;
    northcape_restriction_type_t restriction_type;
    northcape_resolve_error_t error_code;
  } axis_validate_request_tdata_t;

  typedef struct packed {
    segment_base_addr_t address;
    // set to all-0's for invalid segment
    segment_length_t segment_length;
    // device-interpreted restriction or set-task-id restriction
    // otherwise meaningless
    northcape_restriction_body_t restriction;
    // only NORTHCAPE_RESTRICTIONS_SET_TASK_ID, NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED should be conveyed
    northcape_restriction_type_t restriction_type;
    // whether the data/instructions in the capability may be cached
    // permissions from the top-level CMT entry - primarily for cva6 MMU's cache
    northcape_permissions_t permissions;
    // type of error encountered during resolution
    northcape_resolve_error_t error_code;
  } axis_validate_response_tdata_t;

  localparam AXIS_VALIDATE_RESPONSE_TDATA_WIDTH = $bits(axis_validate_response_tdata_t);
  localparam AXIS_VALIDATE_RESPONSE_TID_WIDTH = 1;
  localparam AXIS_VALIDATE_RESPONSE_TDEST_WIDTH = $bits(device_id_t);
  localparam AXIS_VALIDATE_RESPONSE_TUSER_WIDTH = 1;

  localparam AXIS_VALIDATE_REQUEST_TDATA_WIDTH = $bits(axis_validate_request_tdata_t);
  localparam AXIS_VALIDATE_REQUEST_TID_WIDTH = 1;
  localparam AXIS_VALIDATE_REQUEST_TDEST_WIDTH = 1;
  localparam AXIS_VALIDATE_REQUEST_TUSER_WIDTH = 1;

  // this is shared between several MMU modules...
  typedef enum {
    IDLE,
    REQUEST_VALIDATION,
    WAIT_VALIDATION,
    WAIT_ADDRESS_HANDSHAKE,
    FORWARD_ADDR,
    FORWARD_DATA_FIRST_TRANSACTION,
    FORWARD_DATA_LAST_TRANSACTION,
    FORWARD_DATA,
    FORWARD_DATA_ZERO_OUT,
    WAIT_COMPLETE,
    REPORT_ERROR,
    LAST_REPORT_ERROR,
    SINGLE_REPORT_ERROR,
    // AXI spec: can only raise bvalid after wlast
    REPORT_ERROR_BCHAN,
    FORWARD_ATOMIC_TRANSACTION
  } mmu_state_t;


  typedef struct packed {
    northcape_device_interpreted_restriction_t device_interpreted_restriction;
    logic [15:0] reserved;
    device_id_t current_device_id;
    task_id_t current_task_id;
  } northcape_axi_user_t;


  /* CSR request, from CSR to ops */
  typedef enum {
    CSR_READ,
    CSR_WRITE
  } northcape_cap_ops_rcsr_req_type_t;

  /* both IRQ and non-IRQ are accessible */
  typedef logic [2:0] northcape_cap_ops_rcsr_reg_num_t;

  typedef logic [63:0] northcape_cap_ops_rcsr_reg_val_t;

  typedef struct packed {
    logic req_valid;
    northcape_cap_ops_rcsr_req_type_t req_type;
    northcape_cap_ops_rcsr_reg_num_t reg_num;
    northcape_cap_ops_rcsr_reg_val_t reg_new_val;
    device_id_t device_id;
    task_id_t task_id;
    logic is_irq;
  } northcape_cap_ops_rcsr_req_t;

  /* CSR request, from ops to CSR */
  typedef struct packed {
    northcape_cap_ops_rcsr_reg_val_t reg_old_val;
    logic ok;
  } northcape_cap_ops_rcsr_resp_t;

  localparam NORTHCAPE_CAPABILITY_OPS_CSR_INTERFACE_REG_WIDTH_BITS = 64;


endpackage : northcape_types

/**
  * Used for interfacing a test or consumer module with the register interface 
  */
interface NorthcapeRegInterfaceIO #(
    parameter NUM_REGS = -1,
    parameter AXI_DATA_WIDTH = -1
) (
    input logic clk_i
);
  // regs going into the register interface
  logic [AXI_DATA_WIDTH-1:0] regs_in [NUM_REGS];
  // regs coming out of the register interface
  logic [AXI_DATA_WIDTH-1:0] regs_out[NUM_REGS];

`ifndef VERILATOR
  clocking test_regs_clocking @(posedge (clk_i));
    output regs_in;
    input regs_out;
  endclocking
`endif

  modport REG_INTERFACE(input clk_i, regs_in, output regs_out);
  modport USER(input clk_i, output regs_in, input regs_out);

`ifndef VERILATOR
  // TODO not supported
  modport TEST(clocking test_regs_clocking);
`endif
endinterface

/**
  * used to interface the capability operations module with the remaining modules
  * contains metadata regarding the current location of the CMT
  */
interface NorthcapeCMTInterface #(
    parameter AXI_ADDR_WIDTH = -1
) (
    input logic clk_i
);
  // current capability metadata table size log 2 (from operations module)
  int unsigned table_size_clog2;
  // current capability metadata base address
  logic [AXI_ADDR_WIDTH - 1 : 0] cmt_base;
  // raised by ops when reset is done
  logic reset_done;
  // raised when CPUs and other data-caching devices need to flush caches, e.g., after revoke
  logic need_flush_data_caches;

  // used to indicate when a capability was written, and which it was - for cva6 / MMU cache
  logic wrote_any_capability;
  northcape_types::capability_id_t written_capability;

  modport OPS_INTERFACE(
      input clk_i,
      output table_size_clog2, cmt_base, reset_done, need_flush_data_caches, wrote_any_capability, written_capability
  );
  modport CONSUMER(
      input clk_i, table_size_clog2, cmt_base, reset_done, need_flush_data_caches, wrote_any_capability, written_capability
  );

`ifndef VERILATOR

  clocking test_producer_clocking @(posedge (clk_i));
    output table_size_clog2;
    output cmt_base;
    output reset_done;
  endclocking

  modport TEST_PRODUCER(clocking test_producer_clocking);

  clocking test_consumer_clocking @(posedge (clk_i));
    input table_size_clog2;
    input cmt_base;
    input reset_done;
  endclocking

  modport TEST_CONSUMER(clocking test_consumer_clocking);
`endif
endinterface

/**
  * informs the capability operations module which device and task are the origin of the request.
  * extracted from User bits.
  */
interface NorthcapeCurrentDeviceTaskInterface (
    input logic clk_i
);
  northcape_types::device_id_t active_device;
  northcape_types::task_id_t active_task;
  northcape_types::northcape_device_interpreted_restriction_t device_specific_restriction;

  // raised when read and write appear at the same clock flang
  logic parsing_error;

  modport OPS_INTERFACE(
      input clk_i, active_device, active_task, device_specific_restriction, parsing_error
  );
  modport USER_WRAPPER(
      input clk_i,
      output active_device, active_task, device_specific_restriction, parsing_error
  );

`ifndef VERILATOR

  clocking test_producer_clocking @(posedge (clk_i));
    output active_device;
    output active_task;
    output device_specific_restriction;
    output parsing_error;
  endclocking

  modport TEST_PRODUCER(clocking test_producer_clocking);
`endif
endinterface


interface NorthcapeInterruptInterface #(
    parameter NUMBER_INTERRUPT_PINS = -1
) (
    input logic clk_i
);

  logic [NUMBER_INTERRUPT_PINS - 1 : 0] irqs;

  modport IRQ_PRODUCER(input clk_i, output irqs);
  modport IRQ_CONSUMER(input clk_i, input irqs);

`ifndef VERILATOR

  clocking test_consumer_clocking @(posedge (clk_i));
    input irqs;
  endclocking

  modport TEST_CONSUMER(clocking test_consumer_clocking);
`endif

endinterface
