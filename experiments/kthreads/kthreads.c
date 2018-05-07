#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kthread.h>
#include <linux/delay.h>

MODULE_LICENSE("GPL");

static struct task_struct *thread_st;

static int thread_fn(void *unused) {
    set_current_state(TASK_INTERRUPTIBLE);
    while (!kthread_should_stop()) {
        printk(KERN_INFO "Thread is running\n");
        ssleep(5);
    }
    
    printk(KERN_INFO "Thread exiting");
    return 0;
}

static int init_thread(void) {
    printk(KERN_INFO "Creating Thread\n");
    thread_st = kthread_create(thread_fn, NULL, "mykthreads");
    if (thread_st) {
        printk(KERN_INFO "Thread create successfully\n");
        wake_up_process(thread_st);
    }    
    else printk(KERN_INFO "Thread creation failed\n"); 
    
    return 0;
}

static void cleanup_thread(void) {
    printk(KERN_INFO "Cleaning up\n");
    if (thread_st) {
        kthread_stop(thread_st);
        printk(KERN_INFO "Thread stopped in cleanup\n");
    }
}                

module_init(init_thread)
module_exit(cleanup_thread)
