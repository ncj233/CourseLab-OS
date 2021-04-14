/* See COPYRIGHT for copyright information. */

#include <inc/mmu.h>
#include <inc/memlayout.h>
#include <inc/trap.h>

#include <kern/picirq.h>


###################################################################
# exceptions/interrupts
###################################################################

/* TRAPHANDLER defines a globally-visible function for handling a trap.
 * It pushes a trap number onto the stack, then jumps to _alltraps.
 * Use TRAPHANDLER for traps where the CPU automatically pushes an error code.
 *
 * You shouldn't call a TRAPHANDLER function from C, but you may
 * need to _declare_ one in C (for instance, to get a function pointer
 * during IDT setup).  You can declare the function with
 *   void NAME();
 * where NAME is the argument passed to TRAPHANDLER.
 */
#define TRAPHANDLER(name, num)						\
	.globl name;		/* define global symbol for 'name' */	\
	.type name, @function;	/* symbol type is function */		\
	.align 2;		/* align function definition */		\
	name:			/* function starts here */		\
	pushl $(num);							\
	jmp _alltraps

/* Use TRAPHANDLER_NOEC for traps where the CPU doesn't push an error code.
 * It pushes a 0 in place of the error code, so the trap frame has the same
 * format in either case.
 */
#define TRAPHANDLER_NOEC(name, num)					\
	.globl name;							\
	.type name, @function;						\
	.align 2;							\
	name:								\
	pushl $0;							\
	pushl $(num);							\
	jmp _alltraps

.text

/*
 * Lab 3: Your code here for generating entry points for the different traps.
 */
TRAPHANDLER_NOEC(INT0, 0);
TRAPHANDLER_NOEC(INT1, 1);
# skip2
TRAPHANDLER_NOEC(INT3, 3);
TRAPHANDLER_NOEC(INT4, 4);
TRAPHANDLER_NOEC(INT5, 5);
TRAPHANDLER_NOEC(INT6, 6);
TRAPHANDLER_NOEC(INT7, 7);
TRAPHANDLER(INT8, 8);
TRAPHANDLER_NOEC(INT9, 9);
TRAPHANDLER(INT10, 10);
TRAPHANDLER(INT11, 11);
TRAPHANDLER(INT12, 12);
TRAPHANDLER(INT13, 13);
TRAPHANDLER(INT14, 14);
# skip15
TRAPHANDLER_NOEC(INT16, 16);

TRAPHANDLER_NOEC(INT48, T_SYSCALL);



/*
 * Lab 3: Your code here for _alltraps
 */
_alltraps:
	# 1. push values to make the stack look like a struct TrapFrame
	pushl %ds
	pushl %es
	pushal
	# 2. load GD_KD into %ds, %es
	movw $GD_KD, %ax
	movw %ax, %ds
	movw %ax, %es
	# 3. pushl %esp to pass a pointer to the Trapframe as an argument to trap()
	pushl %esp
	# 4. call trap (trap can't return)
	call trap

trap_dead:
	jmp trap_dead