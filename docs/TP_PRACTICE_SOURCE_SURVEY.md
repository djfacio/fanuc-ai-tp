# TP Programming Practice Source Survey

This survey lists sources similar in usefulness to OneRobotics for FANUC TP,
KAREL, and industrial robot programming style. It separates source authority
from practical usefulness.

The intent is to decide what deserves influence over our generated TP style
before implementing more rules.

## Source Quality Levels

| Level | Meaning | How To Use |
| --- | --- | --- |
| A | FANUC official or first-party documentation/training | Can support project rules when consistent with manuals and controller evidence. |
| B | Mature open-source industrial robotics project or broadly used practitioner reference | Good for patterns, architecture, and integration practice; verify controller details. |
| C | Practitioner/community discussion | Useful for style pressure and field reality; do not enforce without corroboration. |
| D | Vendor/SEO/tutorial content or mirrored PDFs | Use cautiously; good for leads, not authority. |

## Strong Candidates

### FANUC America Tech Transfer

Quality level: A

Useful links:

- FANUC Run Command Parallel Processing  
  https://techtransfer.fanucamerica.com/tech-transfer/fanuc-run-command-parallel-processing
- FANUC Robot Homing Program  
  https://techtransfer.fanucamerica.com/tech-transfer/fanuc-robot-homing-program
- FANUC Skip Function  
  https://techtransfer.fanucamerica.com/tech-transfer/fanuc-skip-function
- Advanced TPP Programming Mixed Logic and Background Tasks  
  https://techtransfer.fanucamerica.com/tech-transfer/advanced-tpp-programming-mixed-logic-and-background-tasks
- ASCII Program Loader  
  https://techtransfer.fanucamerica.com/tech-transfer/ascii-program-loader
- KAREL and User Socket Messaging  
  https://techtransfer.fanucamerica.com/tech-transfer/karel-amp-user-socket-messaging
- FANUC Backup and Restore Files  
  https://techtransfer.fanucamerica.com/tech-transfer/fanuc-backup-and-restore-files

Observed practice pressure:

- `RUN` is true concurrency, not a blocking call.
- Non-motion concurrent tasks should not own the motion group.
- Homing/recovery programs should reason from actual robot position and use
  ordered guards.
- Skip/search routines should handle both found and not-found cases, including
  user alarm behavior.
- Mixed logic, background tasks, markers, autoexec, and Home IO are real FANUC
  tools that can simplify some IO logic, but they also introduce background
  execution ownership concerns.
- LS generation is a first-party supported path when the controller has the
  right option, and large generated paths may be split into subprograms.
- Backups should include the robot data that actually defines the application:
  TP programs, registers, PRs, and frame data.

Comparison to our current rules:

- Strongly supports our `RUN` ownership rule.
- Supports explicit group mask policy for no-motion tasks.
- Supports explicit homing/recovery guard design.
- Supports generated LS as a legitimate artifact, but our current controller
  lacks ASCII Upload, so MakeTP/TP upload remains the practical route.
- Adds a future topic: background logic/markers should be treated like async
  tasks and included in dependency/recovery analysis.

### FANUC ROS 2 Driver Documentation

Quality level: A

Useful links:

- FANUC ROS 2 driver docs  
  https://fanuc-corporation.github.io/fanuc_driver_doc/main/docs/fanuc_driver/fanuc_driver.html
- FANUC Open Platform ROS driver announcement/download page  
  https://www.fanuc.co.jp/en/product/robot/academia/ros_driver.html

Observed practice pressure:

- FANUC is publishing first-party external-control documentation and GitHub
  workflows for supported controller/software versions.
- External control should be treated as a versioned capability tied to specific
  controller software.

Comparison to our current rules:

- Supports controller-inventory/capability discovery before enabling an
  interface.
- Good architecture reference for future external-control phases, but not a TP
  style guide.

### FANUC HandlingTool / Teach Pendant / KAREL Manuals

Quality level: A when sourced from local trusted manuals or FANUC-controlled
channels.

Observed practice pressure:

- This remains the authority for syntax, group masks, system variables,
  KAREL built-ins, PR behavior, background logic, comments/remarks, and option
  availability.

Comparison to our current rules:

- Use manuals to confirm any generator-enforced behavior, especially PR
  calculations, KAREL APIs, group masks, UOP, BG logic, system variables, and
  Robot Server/SNPX behavior.
- Avoid random public PDF mirrors as authority. They can be search leads only.

### Control.com FANUC Programming Articles

Quality level: B/C

Useful links:

- Introduction to FANUC Robot Programming  
  https://control.com/technical-articles/introduction-to-fanuc-robot-programming/
- FANUC Robot Programming Example  
  https://control.com/technical-articles/fanuc-robot-programming-example/

Observed practice pressure:

- Organize registers, PRs, flags, fieldbus IO, and frames by functional groups.
- Keep comments short enough to fit the pendant.
- Set `UFRAME` and `UTOOL` at the beginning of motion routines because they can
  change between routines.
- Use a main routine that loops, receives/selects commands, calls compact
  function routines, and handles invalid commands.
- Keep routines compact and single-function, even if that creates more routines.

Comparison to our current rules:

- Strong support for project cell maps and resource grouping.
- Strong support for compact function routines and a coordinator-style `A_MAIN`.
- Supports our frame/tool/payload setup rule.
- Good argument for reserving spare registers/PRs within grouped ranges.

### Robot-Forum FANUC Programming Style Discussions

Quality level: C

Useful link:

- Programming Styles thread  
  https://www.robot-forum.com/robotforum/thread/31956-programming-styles/

Observed practice pressure:

- Community discussion commonly frames style as vertical programming versus
  horizontal programming.
- The thread shows strong preference for using more smaller programs once code
  becomes reusable, while still acknowledging both styles have a place.

Comparison to our current rules:

- Supports the user's preference for tiny routines when they name a reusable
  cell concept.
- Also supports our guard against over-fragmentation: horizontal style is useful
  when it improves reuse/readability, not when it hides one-off syntax.

### ROS-Industrial FANUC Support

Quality level: B

Useful links:

- ROS-Industrial FANUC repository  
  https://github.com/ros-industrial/fanuc
- ROS package overview  
  https://index.ros.org/p/fanuc_driver/

Observed practice pressure:

- Mature open-source integration separates robot-resident KAREL/TP from PC-side
  nodes and robot model/support packages.
- Support level and version compatibility are explicit.
- It is not OEM official support; the repository itself points users to FANUC
  branch support for official ROS 1 driver needs.

Comparison to our current rules:

- Strong support for versioned interface contracts and capability inventory.
- Strong support for separating robot-resident code from PC-side services.
- Useful for KAREL/TP integration architecture, not pendant TP style.

### DIY Robotics FANUC Workcell Tips

Quality level: C

Useful link:

- 5 Tips for Programming Your FANUC Work Cell  
  https://diy-robotics.com/blog/fanuc-robot-programming-tips/

Observed practice pressure:

- Plan the structure before programming.
- Do root-cause analysis before applying patches.
- Search libraries, forums, GitHub, and training resources before reinventing.

Comparison to our current rules:

- Supports workflow-first generation and review packets.
- Supports our decision to learn from OneRobotics, ROS-Industrial, manuals, and
  existing HMI/SNPX work before inventing new tools.
- Not detailed enough to drive TP style by itself.

## Useful But Lower-Authority Sources

### RoboDK FANUC Programming Content

Quality level: C/D

Useful link:

- 5 Expert Ways to Program a FANUC Robot  
  https://robodk.com/blog/5-ways-to-program-a-fanuc-robot/

Usefulness:

- Good for comparing teach pendant, text-based offline programming, simulation,
  and offline programming workflows.
- Biased toward RoboDK's product category, so do not use it as authority for
  generated TP style.

### Industrial Monitor Direct Articles

Quality level: D unless corroborated.

Usefulness:

- Sometimes surfaces relevant topics such as vertical vs horizontal programming
  and KAREL TP parsing.
- Recent articles look useful as search leads, but they should be corroborated
  against manuals, FANUC Tech Transfer, or tested controller behavior before
  becoming rules.

### Reddit / r/FANUC / r/PLC Discussions

Quality level: C/D

Usefulness:

- Good for field reality, pain points, and how technicians talk about FANUC.
- Not authoritative. Use only as a smell test or to discover topics to verify.

## Sources To Avoid As Authority

- Random public PDF mirrors of FANUC manuals.
- Scribd/Studylib uploads unless the same manual is present in our trusted local
  manual project.
- AI-generated SEO articles with no named industrial author or test evidence.

These may help discover keywords, but they should not support generator rules.

## Initial Ranking For Our Project

1. Local FANUC manuals and FANUC Tech Transfer.
2. OneRobotics.
3. Control.com FANUC programming articles.
4. ROS-Industrial FANUC / FANUC ROS 2 docs for external interface architecture.
5. Robot-Forum style discussions as community pressure.
6. DIY Robotics for planning/root-cause workflow.
7. RoboDK and Industrial Monitor Direct as low-authority topic leads only.

## Candidate Rules To Compare Later

These sources suggest the following additions or refinements:

1. Background logic, markers, autoexec, Home IO, and macro programs must be
   treated as async/background dependencies in workflow analysis.
2. Register, PR, flag, IO, alarm, and frame ranges should reserve gaps for
   future additions.
3. Motion routines should set or assert `UFRAME_NUM`, `UTOOL_NUM`, and payload
   at entry unless a project explicitly owns inheritance.
4. Search/skip routines need both found and not-found outcomes, with alarm or
   recovery behavior for not-found.
5. Homing routines need ordered guards based on actual robot position and clear
   assumptions about safe regions.
6. Generated external-control interfaces must be versioned by controller
   software, options, and robot-resident dependencies.
7. Horizontal/tiny-routine style should be encouraged when routines name stable
   cell concepts, not when they wrap arbitrary TP syntax.
