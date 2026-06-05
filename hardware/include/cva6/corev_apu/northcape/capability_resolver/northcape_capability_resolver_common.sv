/**
  * Shared utilities and structures for capability resolver structures
  */
package northcape_capability_resolver_common;

  import northcape_types::*;

  localparam HASH_TYPE_IDENTITY = 0;
  localparam HASH_TYPE_CRC64 = 1;
  localparam HASH_TYPE_DJB2 = 2;


  typedef struct packed {
    capability_id_t capability_id;
    capability_id_t capability_slot;
    capability_tag_t tag;
    device_id_t device_id;
    task_id_t task_id;
    axis_validate_request_perm_t access_type;

    // for recursion
    axis_validate_request_flags_t flags;
    segment_base_addr_t original_address;
    segment_length_t original_segment_length;
    // did permissions and task ID match for the first capability?
    logic original_permission_tid_match;
    // lock key, collected from lock-holder
    northcape_lock_key_t lock_key;
    // permissions from the original capability
    northcape_permissions_t original_permissions;
    // restriction response for recursion
    northcape_restriction_body_t restriction;
    northcape_restriction_type_t restriction_type;
    // must pad to 8 bits
    northcape_resolve_error_t error_code;
  } capability_resolver_validate_request_with_slot_tdata_t;

  typedef struct packed {
    capability_id_t capability_id;
    capability_tag_t tag;
    axis_validate_request_perm_t access_type;
    device_id_t device_id;
    task_id_t task_id;
    northcape_cmt_entry_t cmt_entry;
    // was this a cache hit? if so, can optionally skip recursion
    logic response_cache_hit;

    // for recursion
    axis_validate_request_flags_t flags;
    segment_base_addr_t original_address;
    segment_length_t original_segment_length;
    // did permissions and task ID match for the first capability?
    logic original_permission_tid_match;
    // permissions from the original capability
    northcape_permissions_t original_permissions;
    // lock key, collected from lock-holder
    northcape_lock_key_t lock_key;
    // restriction response for recursion
    northcape_restriction_body_t restriction;
    northcape_restriction_type_t restriction_type;
    // must pad to 8 bits
    northcape_resolve_error_t error_code;
  } capability_resolver_validate_request_with_entry_tdata_t;
`ifndef ASIC
  // pre-computed CRC table
  // https://github.com/stamparm/cryptospecs/blob/master/hash/sources/crc64.c#L473
  const
  logic [63:0]
  crc_table[256] = {
    64'h0000000000000000,
    64'h42F0E1EBA9EA3693,
    64'h85E1C3D753D46D26,
    64'hC711223CFA3E5BB5,
    64'h493366450E42ECDF,
    64'h0BC387AEA7A8DA4C,
    64'hCCD2A5925D9681F9,
    64'h8E224479F47CB76A,
    64'h9266CC8A1C85D9BE,
    64'hD0962D61B56FEF2D,
    64'h17870F5D4F51B498,
    64'h5577EEB6E6BB820B,
    64'hDB55AACF12C73561,
    64'h99A54B24BB2D03F2,
    64'h5EB4691841135847,
    64'h1C4488F3E8F96ED4,
    64'h663D78FF90E185EF,
    64'h24CD9914390BB37C,
    64'hE3DCBB28C335E8C9,
    64'hA12C5AC36ADFDE5A,
    64'h2F0E1EBA9EA36930,
    64'h6DFEFF5137495FA3,
    64'hAAEFDD6DCD770416,
    64'hE81F3C86649D3285,
    64'hF45BB4758C645C51,
    64'hB6AB559E258E6AC2,
    64'h71BA77A2DFB03177,
    64'h334A9649765A07E4,
    64'hBD68D2308226B08E,
    64'hFF9833DB2BCC861D,
    64'h388911E7D1F2DDA8,
    64'h7A79F00C7818EB3B,
    64'hCC7AF1FF21C30BDE,
    64'h8E8A101488293D4D,
    64'h499B3228721766F8,
    64'h0B6BD3C3DBFD506B,
    64'h854997BA2F81E701,
    64'hC7B97651866BD192,
    64'h00A8546D7C558A27,
    64'h4258B586D5BFBCB4,
    64'h5E1C3D753D46D260,
    64'h1CECDC9E94ACE4F3,
    64'hDBFDFEA26E92BF46,
    64'h990D1F49C77889D5,
    64'h172F5B3033043EBF,
    64'h55DFBADB9AEE082C,
    64'h92CE98E760D05399,
    64'hD03E790CC93A650A,
    64'hAA478900B1228E31,
    64'hE8B768EB18C8B8A2,
    64'h2FA64AD7E2F6E317,
    64'h6D56AB3C4B1CD584,
    64'hE374EF45BF6062EE,
    64'hA1840EAE168A547D,
    64'h66952C92ECB40FC8,
    64'h2465CD79455E395B,
    64'h3821458AADA7578F,
    64'h7AD1A461044D611C,
    64'hBDC0865DFE733AA9,
    64'hFF3067B657990C3A,
    64'h711223CFA3E5BB50,
    64'h33E2C2240A0F8DC3,
    64'hF4F3E018F031D676,
    64'hB60301F359DBE0E5,
    64'hDA050215EA6C212F,
    64'h98F5E3FE438617BC,
    64'h5FE4C1C2B9B84C09,
    64'h1D14202910527A9A,
    64'h93366450E42ECDF0,
    64'hD1C685BB4DC4FB63,
    64'h16D7A787B7FAA0D6,
    64'h5427466C1E109645,
    64'h4863CE9FF6E9F891,
    64'h0A932F745F03CE02,
    64'hCD820D48A53D95B7,
    64'h8F72ECA30CD7A324,
    64'h0150A8DAF8AB144E,
    64'h43A04931514122DD,
    64'h84B16B0DAB7F7968,
    64'hC6418AE602954FFB,
    64'hBC387AEA7A8DA4C0,
    64'hFEC89B01D3679253,
    64'h39D9B93D2959C9E6,
    64'h7B2958D680B3FF75,
    64'hF50B1CAF74CF481F,
    64'hB7FBFD44DD257E8C,
    64'h70EADF78271B2539,
    64'h321A3E938EF113AA,
    64'h2E5EB66066087D7E,
    64'h6CAE578BCFE24BED,
    64'hABBF75B735DC1058,
    64'hE94F945C9C3626CB,
    64'h676DD025684A91A1,
    64'h259D31CEC1A0A732,
    64'hE28C13F23B9EFC87,
    64'hA07CF2199274CA14,
    64'h167FF3EACBAF2AF1,
    64'h548F120162451C62,
    64'h939E303D987B47D7,
    64'hD16ED1D631917144,
    64'h5F4C95AFC5EDC62E,
    64'h1DBC74446C07F0BD,
    64'hDAAD56789639AB08,
    64'h985DB7933FD39D9B,
    64'h84193F60D72AF34F,
    64'hC6E9DE8B7EC0C5DC,
    64'h01F8FCB784FE9E69,
    64'h43081D5C2D14A8FA,
    64'hCD2A5925D9681F90,
    64'h8FDAB8CE70822903,
    64'h48CB9AF28ABC72B6,
    64'h0A3B7B1923564425,
    64'h70428B155B4EAF1E,
    64'h32B26AFEF2A4998D,
    64'hF5A348C2089AC238,
    64'hB753A929A170F4AB,
    64'h3971ED50550C43C1,
    64'h7B810CBBFCE67552,
    64'hBC902E8706D82EE7,
    64'hFE60CF6CAF321874,
    64'hE224479F47CB76A0,
    64'hA0D4A674EE214033,
    64'h67C58448141F1B86,
    64'h253565A3BDF52D15,
    64'hAB1721DA49899A7F,
    64'hE9E7C031E063ACEC,
    64'h2EF6E20D1A5DF759,
    64'h6C0603E6B3B7C1CA,
    64'hF6FAE5C07D3274CD,
    64'hB40A042BD4D8425E,
    64'h731B26172EE619EB,
    64'h31EBC7FC870C2F78,
    64'hBFC9838573709812,
    64'hFD39626EDA9AAE81,
    64'h3A28405220A4F534,
    64'h78D8A1B9894EC3A7,
    64'h649C294A61B7AD73,
    64'h266CC8A1C85D9BE0,
    64'hE17DEA9D3263C055,
    64'hA38D0B769B89F6C6,
    64'h2DAF4F0F6FF541AC,
    64'h6F5FAEE4C61F773F,
    64'hA84E8CD83C212C8A,
    64'hEABE6D3395CB1A19,
    64'h90C79D3FEDD3F122,
    64'hD2377CD44439C7B1,
    64'h15265EE8BE079C04,
    64'h57D6BF0317EDAA97,
    64'hD9F4FB7AE3911DFD,
    64'h9B041A914A7B2B6E,
    64'h5C1538ADB04570DB,
    64'h1EE5D94619AF4648,
    64'h02A151B5F156289C,
    64'h4051B05E58BC1E0F,
    64'h87409262A28245BA,
    64'hC5B073890B687329,
    64'h4B9237F0FF14C443,
    64'h0962D61B56FEF2D0,
    64'hCE73F427ACC0A965,
    64'h8C8315CC052A9FF6,
    64'h3A80143F5CF17F13,
    64'h7870F5D4F51B4980,
    64'hBF61D7E80F251235,
    64'hFD913603A6CF24A6,
    64'h73B3727A52B393CC,
    64'h31439391FB59A55F,
    64'hF652B1AD0167FEEA,
    64'hB4A25046A88DC879,
    64'hA8E6D8B54074A6AD,
    64'hEA16395EE99E903E,
    64'h2D071B6213A0CB8B,
    64'h6FF7FA89BA4AFD18,
    64'hE1D5BEF04E364A72,
    64'hA3255F1BE7DC7CE1,
    64'h64347D271DE22754,
    64'h26C49CCCB40811C7,
    64'h5CBD6CC0CC10FAFC,
    64'h1E4D8D2B65FACC6F,
    64'hD95CAF179FC497DA,
    64'h9BAC4EFC362EA149,
    64'h158E0A85C2521623,
    64'h577EEB6E6BB820B0,
    64'h906FC95291867B05,
    64'hD29F28B9386C4D96,
    64'hCEDBA04AD0952342,
    64'h8C2B41A1797F15D1,
    64'h4B3A639D83414E64,
    64'h09CA82762AAB78F7,
    64'h87E8C60FDED7CF9D,
    64'hC51827E4773DF90E,
    64'h020905D88D03A2BB,
    64'h40F9E43324E99428,
    64'h2CFFE7D5975E55E2,
    64'h6E0F063E3EB46371,
    64'hA91E2402C48A38C4,
    64'hEBEEC5E96D600E57,
    64'h65CC8190991CB93D,
    64'h273C607B30F68FAE,
    64'hE02D4247CAC8D41B,
    64'hA2DDA3AC6322E288,
    64'hBE992B5F8BDB8C5C,
    64'hFC69CAB42231BACF,
    64'h3B78E888D80FE17A,
    64'h7988096371E5D7E9,
    64'hF7AA4D1A85996083,
    64'hB55AACF12C735610,
    64'h724B8ECDD64D0DA5,
    64'h30BB6F267FA73B36,
    64'h4AC29F2A07BFD00D,
    64'h08327EC1AE55E69E,
    64'hCF235CFD546BBD2B,
    64'h8DD3BD16FD818BB8,
    64'h03F1F96F09FD3CD2,
    64'h41011884A0170A41,
    64'h86103AB85A2951F4,
    64'hC4E0DB53F3C36767,
    64'hD8A453A01B3A09B3,
    64'h9A54B24BB2D03F20,
    64'h5D45907748EE6495,
    64'h1FB5719CE1045206,
    64'h919735E51578E56C,
    64'hD367D40EBC92D3FF,
    64'h1476F63246AC884A,
    64'h568617D9EF46BED9,
    64'hE085162AB69D5E3C,
    64'hA275F7C11F7768AF,
    64'h6564D5FDE549331A,
    64'h279434164CA30589,
    64'hA9B6706FB8DFB2E3,
    64'hEB46918411358470,
    64'h2C57B3B8EB0BDFC5,
    64'h6EA7525342E1E956,
    64'h72E3DAA0AA188782,
    64'h30133B4B03F2B111,
    64'hF7021977F9CCEAA4,
    64'hB5F2F89C5026DC37,
    64'h3BD0BCE5A45A6B5D,
    64'h79205D0E0DB05DCE,
    64'hBE317F32F78E067B,
    64'hFCC19ED95E6430E8,
    64'h86B86ED5267CDBD3,
    64'hC4488F3E8F96ED40,
    64'h0359AD0275A8B6F5,
    64'h41A94CE9DC428066,
    64'hCF8B0890283E370C,
    64'h8D7BE97B81D4019F,
    64'h4A6ACB477BEA5A2A,
    64'h089A2AACD2006CB9,
    64'h14DEA25F3AF9026D,
    64'h562E43B4931334FE,
    64'h913F6188692D6F4B,
    64'hD3CF8063C0C759D8,
    64'h5DEDC41A34BBEEB2,
    64'h1F1D25F19D51D821,
    64'hD80C07CD676F8394,
    64'h9AFCE626CE85B507
  };
`endif
  /**
      * Computes a hash over the given capability ID.
      * HASH_TYPE indicates which hash function to use (currently HASH_TYPE_IDENTITY, HASH_TYPE_CRC64, HASH_TYPE_DJB2)
      */
  class NorthcapeCapabilityResolverHash #(
      parameter int HASH_TYPE = -1
  );
`ifndef ASIC
    static function automatic bit [63:0] compute_hash_crc64(input capability_id_t capability_id);
      bit [63:0] crc;
      bit [ 7:0] tab_index;

      crc = '1;

      for (int i = 0; i < $bits(capability_id) / 8; i++) begin
        tab_index = ((crc >> 56) ^ capability_id[i+:8]) & 8'hff;
        crc = crc_table[tab_index] ^ (crc << 8);
      end

      crc = crc ^ '1;

      return crc;

    endfunction
`endif
    static function automatic bit [63:0] compute_hash_djb2(input capability_id_t capability_id);
      bit [63:0] hash;
      bit [63:0] extended_input;

      hash = 5381;
      extended_input = capability_id;

      for (int i = 0; i < $bits(extended_input) / 8; i++) begin
        hash = ((hash << 5) + hash) + extended_input[i+:8];
      end

      return hash;

    endfunction

    static function automatic capability_id_t compute_hash(input capability_id_t capability_id,
                                                           input int table_size_clog_2);
      bit [63:0] ret;
      unique case (HASH_TYPE)
`ifndef ASIC
        HASH_TYPE_CRC64: ret = compute_hash_crc64(capability_id);
`endif
        HASH_TYPE_DJB2: ret = compute_hash_djb2(capability_id);
        HASH_TYPE_IDENTITY: ret = capability_id;
`ifndef ASIC
        default: $error("Unsupported hash type!");
`endif
      endcase

`ifdef DEBUG
      $display("Computed full precision hash %x for input %d mask %x", capability_id, ret,
               (1 << table_size_clog_2) - 1);
`endif

      return ret & ((1 << table_size_clog_2) - 1);
    endfunction
  endclass

endpackage
