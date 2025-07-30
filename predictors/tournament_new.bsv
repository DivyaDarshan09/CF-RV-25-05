// See LICENSE.iitm for license details
/*
Author : Goutham V
Tournament Branch Predictor - Combination of GShare and Bimodal Predictor
--------------------------------------------------------------------------------------------------
*/
package tournament_new;
/*===== Imports =====*/
import FIFO::*;
import FIFOF::*;
import Connectable::*;
import ConfigReg::*;
import GetPut::*;
import bimodal_gs::*;
import gshare_fa::*;
import mem_config::*;
import Assert::*;
import OInt::*; // for indexing if needed
import Vector::*;
  `include "ccore_params.defines"
  import ccore_types :: *;
`include "Logger.bsv"

`define ignore 1
`define TournSize 1024 // adjust if needed

interface Ifc_bpu;
   method ActionValue#(PredictionResponse) mav_prediction_response (PredictionRequest r);
   method Action ma_train_bpu (Training_data td);
   method Action ma_mispredict (Tuple2#(Bool, Bit#(`histlen)) g);
   method Action ma_bpu_enable (Bool e);
 endinterface

(* synthesize *)
module mkbpu#(parameter Bit#(`xlen) hartid) (Ifc_bpu);

  // Submodules
  Ifc_bpu_gs gshare <- mkgshare(hartid);
  Ifc_bpu_bm bimodal <- mkbimodal(hartid);

  // Meta predictor
  Vector#(`TournSize, Reg#(Bit#(2))) meta_table <- replicateM(mkReg(2)); // 2 = weakly favor gshare

  // Save prediction inputs/outputs
  Reg#(PredictionRequest) rg_req <- mkRegU;
  Reg#(Bit#(2)) rg_g_pred <- mkReg(1);
  Reg#(Bit#(2)) rg_b_pred <- mkReg(1);
  Reg#(PredictionResponse) rg_g_resp <- mkRegU;
  Reg#(PredictionResponse) rg_b_resp <- mkRegU;

  // Enable
  Wire#(Bool) wr_bpu_enable <- mkWire();
  // Initialization rule
  `ifdef ifence
  ConfigReg#(Bool) rg_initialize <- mkConfigReg(False);
rule rl_initialize (rg_initialize);
  // Reset meta_table entries to 2 (weakly favor gshare)
  for (Integer i = 0; i < valueOf(`TournSize); i = i + 1) begin
    meta_table[i] <= 2;
  end

  // Reset other registers
  rg_req <= ?;
  rg_g_pred <= 1;
  rg_b_pred <= 1;
  rg_g_resp <= ?;
  rg_b_resp <= ?;

  // Clear the initialization flag
  rg_initialize <= False;
endrule
`endif 
  method ActionValue#(PredictionResponse) mav_prediction_response(PredictionRequest r) if(wr_bpu_enable && !rg_initialize);
    // Save request
    `ifdef ifence
      if( r.fence && wr_bpu_enable)
        rg_initialize <= True;
    `endif
    rg_req <= r;

    // Ask both predictors
    PredictionResponse g_resp <- gshare.mav_prediction_response_g(r);
    PredictionResponse b_resp <- bimodal.mav_prediction_response_b(r);

    rg_g_resp <= g_resp;
    rg_b_resp <= b_resp;

    Bit#(2) g_pred_val = g_resp.btbresponse.prediction;
    Bit#(2) b_pred_val = b_resp.btbresponse.prediction;

    rg_g_pred <= g_pred_val;
    rg_b_pred <= b_pred_val;

    // Meta-index
    Bit#(TLog#(`TournSize)) idx = truncateLSB(r.pc >> `ignore);
    Bit#(2) meta = meta_table[idx];

    Bool prefer_gshare = (meta >= 2);

    // Explicit result declaration
    PredictionResponse final_resp;
    if (prefer_gshare) begin
        final_resp = g_resp;
    end else begin
        final_resp = b_resp;
    end

    `logLevel(tournament, 0, $format("[%2d] TOURNAMENT: PC=%h meta=%0d pick=%s", hartid,r.pc, meta, prefer_gshare ? "GSHARE" : "BIMODAL"))

    return final_resp;
endmethod


  method Action ma_train_bpu(Training_data td)if (wr_bpu_enable && !rg_initialize);
    Bit#(TLog#(`TournSize)) idx = truncateLSB(td.pc >> `ignore);

    Bool g_pred = (rg_g_pred > 1);
    Bool b_pred = (rg_b_pred > 1);
    Bool actual_taken = (td.state > 1);

    if (g_pred != b_pred) begin
      if (g_pred == actual_taken) begin
        if (meta_table[idx] == 2'b11)
          meta_table[idx] <= 2'b11;
        else
          meta_table[idx] <= meta_table[idx] + 2'b01;
      end else begin
        if (meta_table[idx] == 2'b00)
          meta_table[idx] <= 2'b00;
        else
          meta_table[idx] <= meta_table[idx] - 2'b01;
      end
    end

    gshare.ma_train_bpu_g(td);
    bimodal.ma_train_bpu_b(td);
endmethod



  method Action ma_mispredict(Tuple2#(Bool, Bit#(`histlen)) g) if (!rg_initialize);
    gshare.ma_mispredict_g(g);
    bimodal.ma_mispredict_b(g);
  endmethod

  method Action ma_bpu_enable(Bool e);
    wr_bpu_enable <= e;
    gshare.ma_bpu_enable_g(e);
    bimodal.ma_bpu_enable_b(e);
  endmethod

endmodule

endpackage
