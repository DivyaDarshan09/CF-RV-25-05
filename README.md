# CF-RV-25-05: Tournament Branch Predictor for Shakti C-Class

This project was developed as part of the **CEG Fabless RISC-V Internship**, a collaborative initiative between **College of Engineering, Guindy (CEG)**, **Vyoma Systems**, and the **Shakti Processor Team (IIT Madras)**.

---

## Project Overview

Our primary objective was to **design and integrate a tournament branch predictor** into the **Shakti C-Class processor** and to **revamp the existing bimodal predictor**. This enhancement improves the accuracy of branch prediction in RISC-V cores by dynamically choosing between two predictors: **Gshare** and **Bimodal**.

---

## What is a Branch Predictor?

In pipelined processors, **branch instructions** (like `if` statements or loops) can disrupt instruction flow. To maintain high performance, processors use **branch predictors** to *guess the outcome* of a branch **before** it is resolved. This allows the pipeline to continue fetching and executing instructions without stalling.

Without prediction, the processor would have to wait for the branch to resolve, causing performance degradation.

---

##  Types of Branch Predictors

### 1. **Static Branch Predictors**
- Always predict the same outcome (e.g., always taken or always not taken).
- Simple but often inaccurate in real-world code.

### 2. **Dynamic Branch Predictors**
Use runtime behavior to improve accuracy.

#### a. **Bimodal Predictor**
- Uses a single-bit or 2-bit counter per branch address.
- Predicts taken or not-taken based on recent outcomes.
- Simple and fast, but may mispredict in certain patterns.

#### b. **Gshare Predictor**
- Uses the XOR of the Global History Register (GHR) and branch address to index a table of counters.
- Better at handling global patterns and loops.
- More accurate than bimodal for complex control flows.

#### c. **Tournament Predictor**
- Combines two or more predictors (e.g., bimodal and gshare).
- Uses a selection mechanism (meta-predictor) to choose the better predictor for each branch.
- Offers high accuracy across diverse code patterns.

---

##  Domain - RTL Core/Debug Team

---

##  Objectives

- [x] Implement a **Tournament Branch Predictor** using Gshare and Bimodal logic.
- [x] Revamp the existing **Bimodal Predictor** in the Shakti C-Class.
- [x] Integrate and test the enhanced predictor within the processor pipeline.

---

##  Technologies & Tools

- **Bluespec Verilog**
- **Shakti C-Class Core**
- **Git & GitHub**
- **linux**
- **GNU RISC-V Toolchain**

---

##  References

- [Shakti Processor Documentation](https://shakti.org.in)
- [RISC-V Specifications](https://riscv.org/technical/specifications/)

---

## Contributors

- **Divya Darshan** – 2023105032  
- **Goutham Badhrinath** – 2023105036  

ECE, 3rd Year  
College of Engineering, Guindy  
Anna University, Chennai

---

## 📄 License

This project is open-sourced under the MIT License.

