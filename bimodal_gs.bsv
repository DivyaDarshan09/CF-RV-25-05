// See LICENSE.iitm for license details
/*

Author : IIT Madras
Details: This module implements a Bimodal branch predictor with
Return-Address-Stack support. It basically has the prediction and training phase. The comments on
the respective methods describe their operations.

--------------------------------------------------------------------------------------------------
*/
package bimodal_gs;

  // -- library imports
  import Assert :: *;
  import ConfigReg :: * ;
  import Vector :: * ;
  import OInt :: * ;
  import RegFile :: * ;

  // -- project imports
  `include "Logger.bsv"
  `include "ccore_params.defines"
  import ccore_types :: *;
`ifdef bpu_ras
  import stack :: * ;
`endif

  `define ignore 2

  // the following macro describes the number of banks the bht array is split into
  `ifdef compressed
    `define bhtcols 2
  `else
    `define bhtcols 1
  `endif

  /*doc:struct: This struct defines the fields of each entry in the Branch-Target-Buffer*/
  typedef struct{
    Bit#(`vaddr)  target;               // full target virtual address
    ControlInsn   ci;                   // indicate the type of entry. Branch, JAL, Call, Ret.
  `ifdef compressed
    Bool instr16 ;                      // when true indicates a 32-bit Ci at non-4-byte address
    Bool hi;                            // when true indicates higher 16-bit is a Ci
  `endif
  } BTBEntry deriving(Bits, Eq, FShow);

  /*doc:struct: This struct holds the tag and valid bit of each BTB entry.
  Each entry corresponds to a tag for a 4-byte aligned address. This means that this tag can be a
  hit of at-most 2 instructions when compressed is supported. To distinguish between the 2
  instructions we have provided a 'hi' field in BTBEntry, which when true indicates that the higher
  instruction within the 4-byte address is a hit/trained */
  typedef struct{
    Bit#(TSub#(`vaddr, 2)) tag;
    Bool valid;
  } BTBTag deriving(Bits, Eq, FShow);


  // To calculate pc for bimodal
  function Bit#(TLog#(TDiv#(`bhtdepth,`bhtcols))) fn_hash (Bit#(`histlen) history, Bit#(`vaddr) pc);
    return truncate(pc >> `ignore);
  endfunction

  interface Ifc_bpu;
    /*doc : method : receive the request of new pc and return the next pc in case of hit. */
    method ActionValue#(PredictionResponse) mav_prediction_response (PredictionRequest r);

    /*doc : method : method to train the BTB and BHT tables based on the evaluation from execute
    stage*/
	  method Action ma_train_bpu (Training_data td);

    // This is exclusive for GShare so noAction
    method Action ma_mispredict (Tuple2#(Bool, Bit#(`histlen)) g);

    /*doc : method : This method captures if the bpu is enabled through csr or not*/
    method Action ma_bpu_enable (Bool e);
  endinterface

`ifdef bpu_noinline
`ifdef core_clkgate
  (*synthesize,gate_all_clocks*)
`else
  (*synthesize*)
`endif
`endif
  module mkbimodal#(parameter Bit#(`xlen) hartid) (Ifc_bpu);

    String bpu = "";

  `ifdef bpu_ras
    Ifc_stack#(`vaddr, `rasdepth) ras_stack <- mkstack;
  `endif

    /*doc : vec : This vector of register holds the BTB entries. We use vector instead of array
    to leverage the select function provided by bluespec*/
    Vector#(`btbdepth, Reg#(BTBEntry)) v_reg_btb_entry <-
                                                  replicateM(mkReg(BTBEntry{target: ?, ci : Branch
                                           `ifdef compressed ,instr16: False, hi:False `endif }));

    /*doc : vec : This vector holds the BTB tags and the respecitve valid bits. This has been split
    from the BTB entries for better hw of CAM look-ups and index retrieval */
    Vector#(`btbdepth, Reg#(BTBTag)) v_reg_btb_tag <- replicateM(mkReg(unpack(0)));

    /*doc : reg : This array holds the branch history table. The bht table banked into `bhtcols
    banks. In case of compressed `bhtcols is 2 else 1. By banking it becomes easy to access the bht
    in case of compressed support since we are storing only one BTB per 4-byte align addresses.
    Each entry is `statesize-bits wide and represents a up/down saturated counter.
    The reset value is set to 1 */
    /*Reg#(Bit#(`statesize)) rg_bht_arr[`bhtcols][`bhtdepth/`bhtcols];
    for(Integer i = 0; i < `bhtcols; i =  i + 1)
      for(Integer j = 0; j < `bhtdepth/`bhtcols ; j =  j + 1)
        rg_bht_arr[i][j] <- mkReg(1);*/
    
    RegFile#(Bit#(TLog#(TDiv#(`bhtdepth,`bhtcols))), Bit#(`statesize)) rg_bht_arr[`bhtcols];
    for (Integer i = 0; i<`bhtcols; i = i + 1) begin
      rg_bht_arr[i] <- mkRegFileWCF(0,fromInteger(valueOf(TDiv#(`bhtdepth,`bhtcols))-1));
    end
    /*doc:reg: */
    Reg#(Bit#(TLog#(TDiv#(`bhtdepth, `bhtcols)))) rg_bht_index <- mkReg(0);
    /*doc : reg : This register points to the next entry in the Fully associative BTB that should
    be allocated for a new entry */
    Reg#(Bit#(TLog#(`btbdepth))) rg_allocate <- mkReg(0);

    

    /*doc : wire : This wire indicates if the predictor is enabled or disabled by the csr config*/
    Wire#(Bool) wr_bpu_enable <- mkWire();

  `ifdef ifence
    /*doc : reg : When true this register flushes all the entries and cleans up the btb*/
    ConfigReg#(Bool) rg_initialize <- mkConfigReg(False);

    /*doc : rule : This rule flushes the btb and puts it back to the initial reset state.
    This rule would be called each time a fence.i is being performed. This rule will also reset the
    ghr and rg_allocate register*/
    rule rl_initialize (rg_initialize);
      for(Integer i = 0; i < `btbdepth; i = i + 1)
        v_reg_btb_tag[i]<=unpack(0);
      for(Integer i = 0; i < `bhtcols ; i = i + 1)
        rg_bht_arr[i].upd(rg_bht_index,1);
      if (rg_bht_index == fromInteger(valueOf(TDiv#(`bhtdepth,`bhtcols))-1))
        rg_initialize <= False;
      rg_bht_index <= rg_bht_index + 1;
      //rg_ghr[1] <= 0;
      rg_allocate <= 0;
    `ifdef bpu_ras
      ras_stack.clear;
    `endif
    endrule
  `endif

    /*doc:method: This method provides prediction for a requested PC.
    If a fence.i is requested, then the rg_initialize register is set to true.

    The index of the bht is obtained using the hash function. This index is then used to find the entry in the BHT.

    We then perform a fully-associative look-up on the BTB. We compare the tags with the pc and
    check for the valid bit to be set. This applied to each entry and a corresponding bit is set in
    match_ variable. By nature of how training and prediction is performed, we expect match_
    variable to be a one-hot vector i.e. only one entry is a hit in the entire BTB. Multiple entries
    can't be a hit since update comes from only one source.

    Then using the match_ variable and the special select function from BSV we pick out the entry
    that is a hit. A hit is detected only is OR(match) != 0.

    Depending on the ci type the prediction variable is set either to 3 or the value in the BHT
    entry that we indexed earlier.

    In case of a BTB hit and the ci being a Branch, the ghr is left-shifted and the lsb is set to 1
    if predicted taken else 0. This ghr is also sent back out along with the prediction and target
    address.

    We also send out a boolean value indicating if the pc caused a hit in the BTB or not.

    Fence: This feature is required for self-modifying codes. Software is required to conduct an
    fence.i each time the text-section is modified by the software. When this happens we need to
    flush the branch predictor as well else non-branch instructions could be treated as predicted
    taken leading to wrong behavior

    Working of RAS: Earlier versions of the predictor included a separate method which would push
    the return address onto the RAS. This address came from the execute stage which when a Call
    instruction was detected. If the BTB was a hit for a pc and it detected a Ret type ci then the
    RAS popped. However with this architecture you could have a push happening from an execute stage
    and a ret being detected in the predictor, this return would never see this latest push and thus
    would pick the wrong address from the RAS. So essentially the RAS would work only if the
    call-ret are a few number of instructions apart, for smaller functions the RAS would fail
    consistently.

    To fix this problem, we push and pop with the predictor itself. If a pc is a btb hit and is a
    Call type ci, the pc+4 value if pushed on the Stack. If the subsequent pc was a btb hit and a
    Ret type ci, it would immediately pick up the RAS top which would be correct. Thus, an empty
    function would also benefit from this mechanism.
    */
    method ActionValue#(PredictionResponse) mav_prediction_response (PredictionRequest r)
                                                         `ifdef ifence if(!rg_initialize) `endif ;
      `logLevel( bpu, 0, $format("[%2d] Bimodal BPU : Received Request: ",hartid, fshow(r)))
    `ifdef ifence
      if( r.fence && wr_bpu_enable)
        rg_initialize <= True;
    `endif
      let bht_index_ = fn_hash(?, r.pc);//changed
      Bit#(`statesize) branch_state_ [`bhtcols];
      for(Integer i = 0; i < `bhtcols ; i = i + 1)
        branch_state_[i] = rg_bht_arr[i].sub(bht_index_);

      Bit#(`statesize) prediction_ = 1;
      Bit#(`vaddr) target_ = r.pc;
      Bool hit = False;
      Bool hi = False;
    `ifdef compressed
      Bool instr16 = False;
    `endif

      if(!r.fence && wr_bpu_enable) begin
        // a one - hot vector to store the hits of the btb
        Bit#(`btbdepth) match_;
        for(Integer i = 0; i < `btbdepth; i =  i + 1)
          match_[i] = pack(v_reg_btb_tag[i].tag == truncateLSB(r.pc) && v_reg_btb_tag[i].valid);

        `logLevel( bpu, 1, $format("[%2d]Bimodal BPU : Match:%h",hartid, match_))

        hit = unpack(|match_);
        let hit_entry = select(readVReg(v_reg_btb_entry), unpack(match_));

        if(|match_ == 1) begin
          `logLevel( bpu, 1, $format("[%2d]Bimodal BPU : BTB Hit: ",hartid,fshow(hit_entry)))
        end

        `ifdef compressed
          instr16 = hit_entry.instr16;
          hi = hit_entry.hi;
        `endif

        if(|match_ == 1) begin
        `ifdef bpu_ras
          `ifdef compressed
            Bit#(`vaddr) ras_push_offset = hit_entry.hi? hit_entry.instr16? r.discard? 2: 4
                                                                          : r.discard? 4: 6
                                                       : hit_entry.instr16? 2: 4;
          `else
            Bit#(`vaddr) ras_push_offset = 4;
          `endif
        if(True `ifdef compressed && ( hit_entry.hi || !r.discard ) `endif ) begin
          if(hit_entry.ci == Call)begin // push to ras in case of Call instructions
            Bit#(`vaddr) push_pc = r.pc + ras_push_offset;
            `logLevel( bpu, 1, $format("[%2d]Bimodal BPU: Pushing1 to RAS:%h",hartid,(push_pc)))
            ras_stack.push(push_pc);
          end

          if(hit_entry.ci == Ret) begin // pop from ras in case of Ret instructions
            target_ = ras_stack.top;
            ras_stack.pop;
            `logLevel( bpu, 1, $format("[%2d]Bimodal BPU: Choosing from top RAS:%h",hartid,target_))
          end
          else
        `endif
          target_ = hit_entry.target;

          // update only if hi is True or if discard is false. No point in predicting dicarded inst.
            if(hit_entry.ci == Ret ||  hit_entry.ci == Call || hit_entry.ci == JAL )
               prediction_ = 3;

            if(hit_entry.ci == Branch) begin
              prediction_ = branch_state_[pack(hi)];
            end
          end

        end
      `ifdef ifence if(!r.fence) `endif

        `logLevel( bpu, 0, $format("[%2d]Bimodal BPU : BHTindex_:%d Target:%h Pred:%d",hartid, bht_index_, target_, prediction_))

        `ifdef ASSERT
          dynamicAssert(countOnes(match_) < 2, "Multiple Matches in BTB");
        `endif
      end

      let btbresponse = BTBResponse{prediction: prediction_, btbhit: hit
                        `ifdef compressed , hi: hi `endif
                        `ifdef gshare , history : ?`endif };

      return PredictionResponse{ nextpc : target_, btbresponse: btbresponse
                                `ifdef compressed ,instr16 : instr16 `endif };
    endmethod

    /*doc:method: This method is called for all unconditional and conditional jumps.
    Using the pc of the instruction we first check if the entry already exists in the btb or not. If
    it does then entry is updated with a new/same target from the execute stage.

    If the entry does not exists then a new entry is allotted in the btb depending on rg_allocate
    value.

    Additionally in case of conditional branches, the bht is again indexed using the pc.
    This entry is updated only if the BTB was a hit during prediction i.e. only on the second
    instance of the branch the bht gets updated.

    It was first thought to be better to send the btbindex along the pipe to reduce the additional
    look-up hw here. However, for really small loops its possible that while training for an entry
    in a cycle, the same instruction is getting predicted again. This will cause a miss in the
    prediction and the training of the second instance would lead to allocating a new entry. This
    would lead to duplicates and thus would require zapping them - another simultaneous look-up. It
    seems the current approach does to seem close on required frequencies.
    */
    method Action ma_train_bpu (Training_data d) if(wr_bpu_enable
                                                          `ifdef ifence && !rg_initialize `endif );
      `logLevel( bpu, 4, $format("[%2d]Bimodal BPU : Received Training: ",hartid,fshow(d)))

      function Bool fn_tag_match (BTBTag a);
        return  (a.tag == truncateLSB(d.pc) && a.valid);
      endfunction

      let hit_index_ = findIndex(fn_tag_match, readVReg(v_reg_btb_tag));

      if(hit_index_ matches tagged Valid .h) begin
        v_reg_btb_entry[h] <= BTBEntry{ target : d.target, ci : d.ci
                            `ifdef compressed ,instr16: d.instr16, hi:unpack(d.pc[1]) `endif };
        `logLevel( bpu, 4, $format("[%2d]Bimodal BPU : Training existing Entry index: %d",hartid,h))
      end
      else begin
        `logLevel( bpu, 4, $format("[%2d]Bimodal BPU : Allocating new index: %d",hartid,rg_allocate))
        v_reg_btb_entry[rg_allocate] <= BTBEntry{ target : d.target, ci : d.ci
                            `ifdef compressed ,instr16: d.instr16, hi:unpack(d.pc[1]) `endif };
        v_reg_btb_tag[rg_allocate] <= BTBTag{tag: truncateLSB(d.pc), valid: True};
        rg_allocate <= rg_allocate + 1;
        if(v_reg_btb_tag[rg_allocate].valid)
          `logLevel( bpu, 4, $format("[%2d]Bimodal BPU : Conflict Detected",hartid))
      end

      let bht_index_ = fn_hash(?, d.pc);
      if(d.ci == Branch && d.btbhit) begin
        rg_bht_arr[d.pc[1]].upd(bht_index_, d.state);
        `logLevel( bpu, 4, $format("[%2d]Bimodal BPU : Upd BHT entry: %d with state: %d",hartid,
                                                                              bht_index_, d.state))
      end
    endmethod

    
    method Action ma_mispredict (Tuple2#(Bool, Bit#(`histlen)) g);
    noAction;
    endmethod

    method Action ma_bpu_enable (Bool e);
      wr_bpu_enable <= e;
    endmethod

  endmodule
endpackage
