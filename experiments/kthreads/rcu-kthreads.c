#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kthread.h>
#include <linux/delay.h>
#include <linux/slab.h>
#include <linux/list.h>
#include <linux/rculist.h>
#include <linux/spinlock.h>
#include <linux/preempt.h>

struct student {
    int id;
    int has_passed;
    int gpa;
    struct list_head node;
    struct rcu_head rcu;
};	

static LIST_HEAD(students);
static spinlock_t students_lock;

//readers and updater
static struct task_struct *thread_r0;
static struct task_struct *thread_r1;
static struct task_struct *thread_r2;
static struct task_struct *thread_up;

static void add_student(int id, int has_passed, int gpa) {
    struct student *s;
    
    s = kmalloc(sizeof(struct student), GFP_KERNEL);
    if (!s) return;
    
    s->id = id;
    s->has_passed = has_passed;
    s->gpa = gpa;
    
    spin_lock(&students_lock);
    list_add_rcu(&s->node, &students);
    spin_unlock(&students_lock);
}

static int modify_student(int id, int has_passed) {
    struct student *s = NULL;
    struct student *new_s = NULL;
    struct student *old_s = NULL;
    
    rcu_read_lock();
    list_for_each_entry(s, &students, node) {
        if (s->id == id) {
            if (s->has_passed == has_passed) {
                //student is either is already approved or already failed
                rcu_read_unlock(); 
                return -1;
            }
            
            old_s = s;
            break;
        }
    }
    
    new_s = kzalloc(sizeof(struct student), GFP_ATOMIC);
    memcpy(new_s, old_s, sizeof(struct student));
    
    rcu_read_unlock();
    
    new_s->has_passed = has_passed;
    if (has_passed) new_s->gpa = 4;
    else new_s->gpa = 3;
    
    spin_lock(&students_lock);
    list_replace_rcu(&old_s->node, &new_s->node);
    spin_unlock(&students_lock);
    
    synchronize_rcu();
    kfree(old_s);
    return 0;
}    

static void delete_student(int id) {
    struct student *s;
    
    spin_lock(&students_lock);
    list_for_each_entry(s, &students, node) {
        if (s->id == id) {
            list_del_rcu(&s->node);
            spin_unlock(&students_lock);
            
            synchronize_rcu();
            kfree(s);
            printk(KERN_INFO "deleted student %d", id);
            return;
        }
    }
    
    spin_unlock(&students_lock);
    printk(KERN_INFO "missing student");
}    

static int student_status(int id) {
    struct student *s;
    
    rcu_read_lock();
    list_for_each_entry(s, &students, node) {
        if (s->id == id) {
            rcu_read_unlock();
            return s->has_passed;
        }
    }
    
    
    rcu_read_unlock();
    printk(KERN_INFO "missing student");
    return -1;
}

static void print_student(int id) {
    struct student *s;
    
    rcu_read_lock();
    list_for_each_entry(s, &students, node) {
        if (s->id == id) {
            printk(KERN_INFO "student %d has passed: %d, gpa: %d", id, s->has_passed, s->gpa);
            rcu_read_unlock();
            return;
        }
    }
    
    rcu_read_unlock();
    printk(KERN_INFO "missing student");
}

static void print_student_all(void) {
    struct student *s;
    
    rcu_read_lock();
    list_for_each_entry(s, &students, node) {
            printk(KERN_INFO "student %d has passed: %d, gpa: %d", s->id, s->has_passed, s->gpa);
    }
    
    rcu_read_unlock();
}

static int student_reader(void *id) {
    int s_id = *((int *) id);
    set_current_state(TASK_INTERRUPTIBLE);
    
    while (!kthread_should_stop()) {
        set_current_state(TASK_RUNNING);
        print_student(s_id);
        
        set_current_state(TASK_INTERRUPTIBLE);
        ssleep(s_id + 1);
    }
    
    printk(KERN_INFO "Thread %d exiting", s_id);
    return 0;
}

static int student_updater(void *unused) {
    struct student *s;
    
    while (!kthread_should_stop()) {
        set_current_state(TASK_RUNNING);
        list_for_each_entry(s, &students, node) {
            modify_student(s->id, !s->has_passed);
        }    
        
        set_current_state(TASK_INTERRUPTIBLE);
        ssleep(5);
    }
    
    printk(KERN_INFO "Thread updater exiting");
    return 0;
}


static void init_students(void) {
    add_student(0, 1, 4);
    add_student(1, 1, 4);
    add_student(2, 1, 4);
}

static int init_test(void) {
    int id0 = 0, id1 = 1, id2 = 2;
    spin_lock_init(&students_lock);
    
    printk(KERN_INFO "-- students module loaded");
    init_students();
    
    thread_r0 = kthread_run(student_reader, &id0, "reader0-kth");
    thread_r1 = kthread_run(student_reader, &id1, "reader1-kth");
    thread_r2 = kthread_run(student_reader, &id2, "reader2-kth");
    
    thread_up = kthread_run(student_updater, NULL, "updater-kth");
    return 0;
}

static void cleanup_test(void) {
    printk(KERN_INFO "-- cleanup students module");
    
    if (thread_r0) {
        kthread_stop(thread_r0);
        printk(KERN_INFO "Thread reader 0 stopped\n");
    }
    
    if (thread_r1) {
        kthread_stop(thread_r1);
        printk(KERN_INFO "Thread reader 1 stopped\n");
    }
    
    if (thread_r2) {
        kthread_stop(thread_r2);
        printk(KERN_INFO "Thread reader 2 stopped\n");
    }

    if (thread_up) {
        kthread_stop(thread_up);
        printk(KERN_INFO "Thread updater stopped\n");
    }
    
    delete_student(0);
    delete_student(1);
    delete_student(2);
}

module_init(init_test);
module_exit(cleanup_test);
MODULE_LICENSE("GPL");
