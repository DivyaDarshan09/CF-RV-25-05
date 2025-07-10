#  CEG Fabless RISC-V Summer Internship 2025  
###  Collaboration with Vyoma Systems & Shakti Processor Team – IIT Madras
### Domain : Hardware Core/Debug 

##  Problem Statement  
C-Class core RTL implementation and simulation: Implement atleast two different branch predictors and evaluate using set of benchmarks given by Shakti team. Compare performance of existing gshare predictor and the new predictors. Extra credit: Tuning the predictors for higher accuracy/lower misprediction rate.

---

##  Author  
- Name: Divya Darshan VR & Goutham Badhrinath V
 


---

##  Objective  
To enhance branch prediction efficiency in the Shakti C-Class Bluespec Core by:

- Tuning the existing Bimodal predictor
- Designing and integrating a new Tournament predictor
- Evaluating these predictors using CoreMark benchmark results.

---

## Project Plan

### Study the Basics
- Understand branch prediction concepts.
- Focus on the following algorithms:
  - Bimodal
  - GShare
  - Tournament
- Analyze existing correlating branch predictor algorithms.

---

### Analyze Existing BSV Code
- Revamp bimodal_nc.bsv and bimodal_c.bsv.
- Understand integration with the pipeline:
  - Where predictions are made
  - Where updates happen
  - How mispredictions are flushed

---

### Design and Implement Tournament Predictor
- Create new module: Tournament.bsv
  - Internally use tuned bimodal and existing GShare predictors
- Use PredictorSelect.bsv:
  - Implement a 2-bit selector table (saturating counter) to pick the better predictor dynamically
- Integrate into the C-Class core

---

### Simulate and Benchmark
- Run basic RISC-V assembly tests
- Benchmark with CoreMark
- Analyze performance using:
  - Prediction accuracy
  - Misprediction rate
  - Instructions Per Cycle (IPC)
  - Total Cycle Count

---

## File Overview

| File / Module          | Description |
|------------------------|-------------|
| Tournament.bsv       | Predicts using both GShare & Bimodal. Uses selector to choose one. |
| PredictorSelect.bsv  | Maintains 2-bit saturating counters to choose between predictors. |
| bpu.bsv              | Unified branch prediction unit. Imports all predictors. |
| bimodal_nc.bsv       | Revamped non-compressed ISA Bimodal predictor. |
| bimodal_c.bsv        | Revamped compressed ISA Bimodal predictor. |
| gshare_fa.bsv        | Existing fully-associative GShare predictor used in tournament logic. |

---

##  Benchmarking and Evaluation

###  Metrics Collected:
-  Branch Prediction Accuracy
-  Misprediction Rate
-  Instructions Per Cycle (IPC)
-  Total Cycle Count

---

###  Comparisons Made:
- Tuned Bimodal Predictor
- Newly implemented Tournament Predictor

---

## Planned Documentation Works
-  Updated .bsv files with implementation
-  Design explanation and working principle
-  Benchmark report with CoreMark results
-  Project repository with all sources and results

---


