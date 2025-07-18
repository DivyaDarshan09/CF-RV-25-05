package tournament_bpu;

module mktournament_bpu(Ifc_bpu);

  // Submodules: GShare and Bimodal
  Ifc_bpu bimodal <- mkbimodal_c;
  Ifc_bpu gshare  <- mkgshare_fa;

  // Meta predictor table (2-bit saturating counters), initialized to 2 (weakly prefer GShare)
  Vector#(TournSize, Reg#(Bit#(2))) meta_table <- replicateM(mkReg(2));

  // Store the latest request and predictions
  Reg#(PredictionRequest) saved_req <- mkRegU;
  Reg#(Bit#(2)) gshare_pred <- mkReg(1);
  Reg#(Bit#(2)) bimodal_pred <- mkReg(1);

  // Accept prediction request 
  method Action prediction_req(PredictionRequest req);
    saved_req <= req;
    gshare.prediction_req(req);
    bimodal.prediction_req(req);
  endmethod

  // Choose prediction using meta-table
  interface next_pc = interface Get;
    method ActionValue#(NextPC) get();
      let g = await gshare.next_pc.get;
      let b = await bimodal.next_pc.get;

      gshare_pred <= g.prediction0;
      bimodal_pred <= b.prediction0;

      let idx = truncate(saved_req.pc >> 2);
      let meta = meta_table[idx];

      Bit#(2) final_pred = (meta >= 2) ? g.prediction0 : b.prediction0;
      Bit#(`vaddr) final_target = (meta >= 2) ? gshare.predicted_pc.target_pc : bimodal.predicted_pc.target_pc;

      return NextPC {
        va: saved_req.pc,
        discard: False,
        prediction0: final_pred
      };
    endmethod
  endinterface

  // Return predicted_pc from selected predictor
  method NextPC predicted_pc;
    let idx = truncate(saved_req.pc >> 2);
    return (meta_table[idx] >= 2) ? gshare.predicted_pc : bimodal.predicted_pc;
  endmethod

  //Train meta predictor and forward to both predictors 
  method Action train_bpu(Training_data td);
    let idx = truncate(td.pc >> 2);
    let g_pred = (gshare_pred > 1);
    let b_pred = (bimodal_pred > 1);
    let actual = (td.state > 1);

    // Meta predictor update: only if gshare and bimodal differ
    if (g_pred != b_pred) begin
      if (g_pred == actual)
        meta_table[idx] <= (meta_table[idx] == 3) ? 3 : meta_table[idx] + 1;
      else
        meta_table[idx] <= (meta_table[idx] == 0) ? 0 : meta_table[idx] - 1;
    end

    // Forward training data to both predictors
    gshare.train_bpu(td);
    bimodal.train_bpu(td);
  endmethod

  // Return Address Stack support 
  method Action ras_push(Bit#(`vaddr) pc);
    gshare.ras_push(pc);
    bimodal.ras_push(pc);
  endmethod

  // Enable/Disable the BPU 
  method Action bpu_enable(Bool e);
    gshare.bpu_enable(e);
    bimodal.bpu_enable(e);
  endmethod

endmodule

endpackage
