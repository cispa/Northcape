
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/idr.h>
#include <linux/platform_device.h>
#include <linux/slab.h>

#include <linux/cdev.h>
#include <linux/fcntl.h>
#include <linux/fs.h>
#include <linux/ioctl.h>
#include <linux/sched.h>

#include <timer_ioctl.h>

#define PULP_APB_TIMER_REGISTER_OFFSET_TIME 0
#define PULP_APB_TIMER_REGISTER_OFFSET_CTRL 1
#define PULP_APB_TIMER_REGISTER_OFFSET_CMP  2

#define PULP_APB_TIMER_ENABLE_MASK BIT(0)
#define PULP_APB_TIMER_DISABLE_MASK 0

#define PULP_APB_TIMER_CHANNEL_OVERFLOW 0
#define PULP_APB_TIMER_CHANNEL_MATCH 1

#define PULP_APB_TIMER_NUM_CHANNELS 2

typedef bool (*pulp_apb_timer_callback_t)(struct platform_device *pdev, uint32_t current_time, void *cookie);

struct pulp_apb_timer_channel {
    pulp_apb_timer_callback_t callback;
    void *cookie;
	bool callback_is_capability;
};

struct pulp_apb_timer_priv {
	struct cdev char_dev;
	void __iomem *reg;
	// back link for file system stuff
	struct platform_device *pdev;
	// /dev fs entry
	struct device *dev;

	struct pulp_apb_timer_channel channels[PULP_APB_TIMER_NUM_CHANNELS];

	int interface_major;
	int interface_minor;

	uint32_t clock_period_ns;
};


static inline uint64_t pulp_apb_timer_time_to_ns(struct platform_device *pdev, uint64_t time){
	const struct pulp_apb_timer_priv *cfg = platform_get_drvdata(pdev);
	return time * cfg->clock_period_ns;
}

static inline uint32_t pulp_apb_timer_ns_to_cycles(struct platform_device *pdev, uint64_t time_ns){
	const struct pulp_apb_timer_priv *cfg = platform_get_drvdata(pdev);
	return (uint32_t)((time_ns) / cfg->clock_period_ns);
}


static inline uint32_t pulp_apb_timer_get_current_time(struct platform_device *pdev){
	const struct pulp_apb_timer_priv *cfg = platform_get_drvdata(pdev);
    uint32_t *__iomem reg_intf = cfg -> reg;

    reg_intf += PULP_APB_TIMER_REGISTER_OFFSET_TIME;

    return readl(reg_intf);
}

static inline void pulp_apb_timer_set_time(struct platform_device *pdev, uint32_t time){
	const struct pulp_apb_timer_priv *cfg = platform_get_drvdata(pdev);
    uint32_t *__iomem reg_intf = cfg -> reg;

    reg_intf += PULP_APB_TIMER_REGISTER_OFFSET_TIME;

	writel(time, reg_intf);
}

static inline void pulp_apb_timer_schedule_compare_callback(struct platform_device *pdev, uint32_t compare_time, pulp_apb_timer_callback_t callback, void *cookie){
	struct pulp_apb_timer_priv *cfg = platform_get_drvdata(pdev);
    uint32_t *__iomem reg_intf = cfg -> reg;
	struct pulp_apb_timer_channel *channel_data = &cfg->channels[PULP_APB_TIMER_CHANNEL_MATCH];

	dev_dbg(&pdev->dev, "Scheduling callback at %u!",compare_time);

    channel_data -> callback = callback;
    channel_data -> cookie = cookie;
    
    writel(PULP_APB_TIMER_ENABLE_MASK, reg_intf + PULP_APB_TIMER_REGISTER_OFFSET_CTRL);

	writel(compare_time, reg_intf + PULP_APB_TIMER_REGISTER_OFFSET_CMP);

	dev_dbg(&pdev->dev, "Scheduled callback at %u", compare_time);
}

static irqreturn_t pulp_apb_timer_overflow_isr(int irq, void *data){
	struct platform_device *pdev = data;
	const struct pulp_apb_timer_priv *cfg = platform_get_drvdata(pdev);
    uint32_t *reg_intf = cfg -> reg;

    dev_warn(&pdev->dev,"Timer overflow!");
	// acknowledge interrupt to device
	writel(PULP_APB_TIMER_DISABLE_MASK, reg_intf + PULP_APB_TIMER_REGISTER_OFFSET_CTRL);

	return IRQ_HANDLED;
}

static irqreturn_t pulp_apb_timer_compare_isr(int irq, void *data){
	struct platform_device *pdev = data;
    struct pulp_apb_timer_priv *cfg = platform_get_drvdata(pdev);
	struct pulp_apb_timer_channel *channel_data = &cfg->channels[PULP_APB_TIMER_CHANNEL_MATCH];
    uint32_t *reg_intf = cfg -> reg;

	dev_dbg(&pdev->dev, "Received compare interrupt - jumping into callback!");

    // acknowledge interrupt to device
    writel(0, reg_intf + PULP_APB_TIMER_REGISTER_OFFSET_CMP);
    
    if(!channel_data->callback){
        dev_warn(&pdev->dev,"Timer matched but no callback registered!");
    }
    else{
        bool continue_enable;
		continue_enable = channel_data->callback(pdev, pulp_apb_timer_get_current_time(pdev), channel_data -> cookie);
	

        if(continue_enable){
            writel(PULP_APB_TIMER_ENABLE_MASK, reg_intf + PULP_APB_TIMER_REGISTER_OFFSET_CTRL);
        }

		dev_dbg(&pdev->dev, "Callback complete!");
	}
	return IRQ_HANDLED;
}

static int pulp_open(struct inode *inode, struct file *file){
	struct pulp_apb_timer_priv *cfg = container_of(inode->i_cdev, struct pulp_apb_timer_priv, char_dev);

	file->private_data = cfg;

	return 0;
}

static ssize_t pulp_read(struct file *filp, char __user *buf, size_t len, loff_t *off){
	struct pulp_apb_timer_priv *cfg = filp->private_data;

	const uint32_t current_time = pulp_apb_timer_get_current_time(cfg->pdev);

	if(len != sizeof(uint32_t)){
		return -1;
	}

	if(copy_to_user(buf, &current_time, sizeof(current_time))){
		return -1;
	}
	return 0;
}

#define PULP_TIMER_SIGNAL 

static bool timer_callback(struct platform_device *pdev, uint32_t current_time, void *cookie){
	struct task_struct *task = cookie;

	if(send_sig(SIGIO, task, 1)){
		dev_err(&pdev->dev,"Could not send signal!");
	}

	return false;
}

static ssize_t pulp_write(struct file *filp, const char __user *buf, size_t len, loff_t *off){
	struct pulp_apb_timer_priv *cfg = filp->private_data;
	uint32_t set_time;

	if(len != sizeof(uint32_t)){
		return -1;
	}

	if(copy_from_user(&set_time, buf, sizeof(uint32_t))){
		return -1;
	}

	pulp_apb_timer_schedule_compare_callback(cfg->pdev, set_time, timer_callback, current);

	return 0;
}


static long pulp_ioctl(struct file *filp, unsigned int cmd, unsigned long arg){
	struct pulp_apb_timer_priv *cfg = filp->private_data;
	uint64_t cycles_in;
	uint64_t ns_out;

	switch(cmd){
		case IOCTL_TO_NS:
			if(copy_from_user(&cycles_in, (uint64_t*) arg, sizeof(cycles_in))){
				return -EFAULT;
			}
			ns_out = pulp_apb_timer_time_to_ns(cfg->pdev, cycles_in);
			if(copy_to_user((uint64_t*)arg, &ns_out, sizeof(ns_out))){
				return -EFAULT;
			}
			break;
		default:
			return -EINVAL;
	}
	return 0;
}

static struct file_operations file_operations = {
	.owner = THIS_MODULE,
	.read = pulp_read,
	.write = pulp_write,
	.open = pulp_open,
	.unlocked_ioctl = pulp_ioctl
};

static DEFINE_IDR(pulp_timer_ida);
static dev_t devno = 0;
static struct class *pulp_timer_class;

static int pulp_timer_probe(struct platform_device *pdev){
	struct pulp_apb_timer_priv *priv;
	struct resource *res;
	int ret;
	int compare_irq, overflow_irq;
	struct device *device;
	dev_t my_dev;
	
	int minor = idr_alloc(&pulp_timer_ida, NULL, 0, INT_MAX, GFP_KERNEL);

	if(minor < 0){
		dev_err(&pdev->dev, "Could not allocate ID!");
		return minor;
	}

	priv = devm_kzalloc(&pdev->dev, sizeof(*priv), GFP_KERNEL);
	if(!priv){
		dev_err(&pdev->dev, "OOM!");
		return -ENOMEM;
	}

	priv->pdev = pdev;

	platform_set_drvdata(pdev, priv);

	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);

	priv->reg = devm_ioremap_resource(&pdev->dev, res);
	if(IS_ERR(priv->reg)){
		dev_err(&pdev->dev, "Could not remap MMIO!");
		return PTR_ERR(priv->reg);
	}

	ret = of_property_read_u32(pdev->dev.of_node, "pulp,clock-period-ns", &priv->clock_period_ns);
	if(ret){
		dev_err(&pdev->dev, "Could not read clock period!");
		return ret;
	}

	overflow_irq = platform_get_irq(pdev, 0);
	if(overflow_irq < 0){
		dev_err(&pdev->dev, "Could not get overflow IRQ");
		return overflow_irq;
	}
	compare_irq = platform_get_irq(pdev, 1);
	if(compare_irq < 0){
		dev_err(&pdev->dev, "Could not get compare IRQ");
		return compare_irq;
	}
	ret = request_irq(overflow_irq, pulp_apb_timer_overflow_isr, IRQF_SHARED, pdev->name, pdev);
	if(ret){
		dev_err(&pdev->dev, "Could not request overflow ISR");
		return ret;
	}
	ret = request_irq(compare_irq, pulp_apb_timer_compare_isr, IRQF_SHARED, pdev->name, pdev);
	if(ret){
		dev_err(&pdev->dev, "Could not request compare ISR");
		return ret;
	}


	priv->interface_major = MAJOR(devno);
	priv->interface_minor = minor;

	my_dev = MKDEV(priv->interface_major, priv->interface_minor);

	device = device_create(pulp_timer_class, NULL, my_dev, NULL, "pulp_timer%d", minor);

	cdev_init(&priv->char_dev, &file_operations);
	priv->char_dev.owner = THIS_MODULE;

	ret = cdev_add(&priv->char_dev, my_dev, 1);
	if(ret < 0){
		dev_err(&pdev->dev, "Could not add character dev!");
		return ret;
	}

	return 0;
	
}

int pulp_timer_remove(struct platform_device *pdev){
	struct pulp_apb_timer_priv *cfg = platform_get_drvdata(pdev);
  	cdev_del(&cfg->char_dev);
	device_destroy(pulp_timer_class, MKDEV(cfg->interface_major, cfg->interface_minor));

	return 0;
}

static const struct of_device_id pulp_of_match[] = {
    {.compatible = "pulp,apb_timer" },
    { }
};
MODULE_DEVICE_TABLE(of, pulp_of_match);

static struct platform_driver pulp_apb_timer_platform_driver = {
	.probe = pulp_timer_probe,
	.remove = pulp_timer_remove,
	.driver = {
		.name = KBUILD_MODNAME,
		.of_match_table = pulp_of_match
	}
};


static int __init pulp_timer_module_init(void){
	int ret;

	ret = alloc_chrdev_region(&devno, 0, 1, "pulp_timer");
	if(ret < 0){
		printk("Could not request character dev!");
		return ret;
	}

	pulp_timer_class = class_create(THIS_MODULE, "pulp_timer");
	if(IS_ERR(pulp_timer_class)){
		printk("Could not create timer class!");
		return -EINVAL;
	}

	return platform_driver_register(&pulp_apb_timer_platform_driver);
}

static void __exit pulp_timer_exit(void){
	class_destroy(pulp_timer_class);
	unregister_chrdev_region(devno,1);
	platform_driver_unregister(&pulp_apb_timer_platform_driver);
}

module_init(pulp_timer_module_init);
module_exit(pulp_timer_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Anon Author");
MODULE_DESCRIPTION("PULP APB timer driver");
