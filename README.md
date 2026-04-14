# ECSE425 Project
## About
Created as the course project for ECSE425 (Computer Architecture) at McGill University, this is a project that implements a 5-stage pipelined RISC-V processor (p4) and a direct mapped cache (p3). Quick note for the actual development of the processor, see the `p4` branch for the commits and debugging that was done.

## Usage
For this project, [ModelSim](https://en.wikipedia.org/wiki/ModelSim) was used for development and testing.

For the caching part of the project, open the `p3` directory as a project in ModelSim and then run

```bash
source cache_tb.tcl
```

For the processor, open the `p4` directory as a project in ModelSim. You can write your own assembly (`.s`) file in the `riscv_assembler` directory. Then assemble it by changing the file in `__init__.py` and running

```bash
python3 __init__.py
```

Then you must copy the resulting binary `.txt` file into the `p4` directory as `program.txt`. Then you can run the processor using 

```bash
source testbench.tcl
```

Finally, you can view the output files `register_file.txt` and `memory.txt` which contain the register file and memory contents respectively.

## Contributers


**P3 Group Number:** 12

**P4 Group Number:** 30

| Student Name  | GitHub          |
|---------------|-----------------|
| Clara Dupuis  | claradupuis     |
| Trevor Piltch | trevorpiltch    |
| Tim Pham      | timmyhoa        |
| Arthur Huang  | arthurandmuffin |

## License
Course content for [Professor Meyer](https://rssl.ece.mcgill.ca/people/) at McGill University.
