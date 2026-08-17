; test_data_structures.m — Test nimm data structures
;
ENTRY
 WRITE "=== Data Structures ===",!
 SET A = $NI_ARRAY("create","arr1")
 WRITE $NI_ARRAY("add","arr1","hello"),!
 WRITE $NI_ARRAY("add","arr1","world"),!
 WRITE "Array[0]: ",$NI_ARRAY("get","arr1",0),!
 WRITE "Array[1]: ",$NI_ARRAY("get","arr1",1),!
 WRITE "Array len: ",$NI_ARRAY("len","arr1"),!
 SET S = $NI_STACK("create","stk1")
 WRITE $NI_STACK("push","stk1","first"),!
 WRITE $NI_STACK("push","stk1","second"),!
 WRITE "Stack peek: ",$NI_STACK("peek","stk1"),!
 WRITE "Stack pop: ",$NI_STACK("pop","stk1"),!
 WRITE "Stack pop: ",$NI_STACK("pop","stk1"),!
 SET O = $NI_OBJECT("create","obj1")
 WRITE $NI_OBJECT("set","obj1","key1","value1"),!
 WRITE $NI_OBJECT("set","obj1","key2","value2"),!
 WRITE "Object[key1]: ",$NI_OBJECT("get","obj1","key1"),!
 WRITE "Object has key1: ",$NI_OBJECT("has","obj1","key1"),!
 WRITE "Object len: ",$NI_OBJECT("len","obj1"),!
 SET Q = $NI_QUEUE("create","que1")
 WRITE $NI_QUEUE("enqueue","que1","first"),!
 WRITE $NI_QUEUE("enqueue","que1","second"),!
 WRITE "Queue peek: ",$NI_QUEUE("peek","que1"),!
 WRITE "Queue dequeue: ",$NI_QUEUE("dequeue","que1"),!
 WRITE "Queue dequeue: ",$NI_QUEUE("dequeue","que1"),!
 SET ST = $NI_SET("create","set1")
 WRITE $NI_SET("add","set1","alpha"),!
 WRITE $NI_SET("add","set1","beta"),!
 WRITE $NI_SET("add","set1","alpha"),!
 WRITE "Set has alpha: ",$NI_SET("has","set1","alpha"),!
 WRITE "Set len: ",$NI_SET("len","set1"),!
 WRITE "=== Done ===",!
 QUIT
