CHILD ; Test child process for JOB
  SET ^CHILDJOB = $JOB
  QUIT

WRITER ; Write to shared LMDB from child
  SET ^JOBTEST = "CHILD_RAN_"_$H
  QUIT

MULTI ; Multiple entry points
  SET ^MULTI1 = "FIRST"
  QUIT

MULTI2 ; Second entry point
  SET ^MULTI2 = "SECOND"
  QUIT

PARENTJOB ; Parent routine for JOB test
  WRITE "PARENT START",!
  JOB HELLO^JOB_CHILD
  WRITE "PARENT AFTER JOB",!
  QUIT
