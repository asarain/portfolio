/*
 * Driver for Atmel AT32 and AT91 SPI Controllers
 *
 * Copyright (C) 2006 Atmel Corporation
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/clk.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/err.h>
#include <linux/interrupt.h>
#include <linux/spi/spi.h>
#include <linux/slab.h>

#include <asm/io.h>
#include <mach/board.h>
#include <mach/gpio.h>
#include <mach/cpu.h>

#define MIDI9 1
#include "atmel_spi.h"

#ifdef MIDI9
#include "../lib/include/midi9_drivercomm.h"
#include "midi9_pwm.h"
#endif

/*
 * The core SPI transfer engine just talks to a register bank to set up
 * DMA transfers; transfer queue progress is driven by IRQs.  The clock
 * framework provides the base clock, subdivided for each spi_device.
 */
struct atmel_spi {
	spinlock_t		lock;

	void __iomem		*regs;
	int			irq;
	struct clk		*clk;
	struct platform_device	*pdev;
	struct spi_device	*stay;

	unsigned char			   stopping;
	struct list_head	   queue;
	struct spi_transfer	*current_transfer;
	unsigned long		     current_remaining_bytes;
	struct spi_transfer	*next_transfer;
	unsigned long		     next_remaining_bytes;

	void			*buffer;
	dma_addr_t		buffer_dma;
#ifdef MIDI9
    struct midi9_spi midi9spi;
#endif    
};

/* Controller-specific per-slave state */
struct atmel_spi_device {
	unsigned int		npcs_pin;
	u32			csr;
};

#define BUFFER_SIZE		PAGE_SIZE
#define INVALID_DMA_ADDRESS	0xffffffff

/*
 * Version 2 of the SPI controller has
 *  - CR.LASTXFER
 *  - SPI_MR.DIV32 may become FDIV or must-be-zero (here: always zero)
 *  - SPI_SR.TXEMPTY, SPI_SR.NSSR (and corresponding irqs)
 *  - SPI_CSRx.CSAAT
 *  - SPI_CSRx.SBCR allows faster clocking
 *
 * We can determine the controller version by reading the VERSION
 * register, but I haven't checked that it exists on all chips, and
 * this is cheaper anyway.
 */
static bool atmel_spi_is_v2(void)
{
	return !cpu_is_at91rm9200();
}

/*
 * Earlier SPI controllers (e.g. on at91rm9200) have a design bug whereby
 * they assume that spi slave device state will not change on deselect, so
 * that automagic deselection is OK.  ("NPCSx rises if no data is to be
 * transmitted")  Not so!  Workaround uses nCSx pins as GPIOs; or newer
 * controllers have CSAAT and friends.
 *
 * Since the CSAAT functionality is a bit weird on newer controllers as
 * well, we use GPIO to control nCSx pins on all controllers, updating
 * MR.PCS to avoid confusing the controller.  Using GPIOs also lets us
 * support active-high chipselects despite the controller's belief that
 * only active-low devices/systems exists.
 *
 * However, at91rm9200 has a second erratum whereby nCS0 doesn't work
 * right when driven with GPIO.  ("Mode Fault does not allow more than one
 * Master on Chip Select 0.")  No workaround exists for that ... so for
 * nCS0 on that chip, we (a) don't use the GPIO, (b) can't support CS_HIGH,
 * and (c) will trigger that first erratum in some cases.
 *
 * TODO: Test if the atmel_spi_is_v2() branch below works on
 * AT91RM9200 if we use some other register than CSR0. However, don't
 * do this unconditionally since AP7000 has an errata where the BITS
 * field in CSR0 overrides all other CSRs.
 */

static void cs_activate(struct atmel_spi *as, struct spi_device *spi)
{
	struct atmel_spi_device *asd = spi->controller_state;
	unsigned active = spi->mode & SPI_CS_HIGH;
	u32 mr;

	if (atmel_spi_is_v2()) {
		/*
		 * Always use CSR0. This ensures that the clock
		 * switches to the correct idle polarity before we
		 * toggle the CS.
		 */
		spi_writel(as, CSR0, asd->csr);
		spi_writel(as, MR, SPI_BF(PCS, 0x0e) | SPI_BIT(MODFDIS)
				| SPI_BIT(MSTR));
		mr = spi_readl(as, MR);
		gpio_set_value(asd->npcs_pin, active);
	} else {
		u32 cpol = (spi->mode & SPI_CPOL) ? SPI_BIT(CPOL) : 0;
		int i;
		u32 csr;

		/* Make sure clock polarity is correct */
		for (i = 0; i < spi->master->num_chipselect; i++) {
			csr = spi_readl(as, CSR0 + 4 * i);
			if ((csr ^ cpol) & SPI_BIT(CPOL))
				spi_writel(as, CSR0 + 4 * i,
						csr ^ SPI_BIT(CPOL));
		}

		mr = spi_readl(as, MR);
		mr = SPI_BFINS(PCS, ~(1 << spi->chip_select), mr);
		if (spi->chip_select != 0)
			gpio_set_value(asd->npcs_pin, active);
		spi_writel(as, MR, mr);
	}

	dev_dbg(&spi->dev, "activate %u%s, mr %08x\n",
			asd->npcs_pin, active ? " (high)" : "",
			mr);
}

static void cs_deactivate(struct atmel_spi *as, struct spi_device *spi)
{
	struct atmel_spi_device *asd = spi->controller_state;
	unsigned active = spi->mode & SPI_CS_HIGH;
	u32 mr;

	/* only deactivate *this* device; sometimes transfers to
	 * another device may be active when this routine is called.
	 */
	mr = spi_readl(as, MR);
	if (~SPI_BFEXT(PCS, mr) & (1 << spi->chip_select)) {
		mr = SPI_BFINS(PCS, 0xf, mr);
		spi_writel(as, MR, mr);
	}

	dev_dbg(&spi->dev, "DEactivate %u%s, mr %08x\n",
			asd->npcs_pin, active ? " (low)" : "",
			mr);

	if (atmel_spi_is_v2() || spi->chip_select != 0)
		gpio_set_value(asd->npcs_pin, !active);
}

#define NEW_WIGGLER 1
#if     NEW_WIGGLER

#define SPI_RESET_ON   at91_set_gpio_value( AT91_PIN_PB3, 0)
#define SPI_RESET_OFF  at91_set_gpio_value( AT91_PIN_PB3, 1)
#define SPI_DATA_HI    at91_set_gpio_output(AT91_PIN_PB1, 1)/*data line*/
#define SPI_DATA_LO    at91_set_gpio_output(AT91_PIN_PB1, 0)/*data low*/
#define SPI_CLOCK_HI   at91_set_gpio_output(AT91_PIN_PB2, 1)/*data line*/
#define SPI_CLOCK_LO   at91_set_gpio_output(AT91_PIN_PB2, 0)/*data low*/

//bit reversed
void midi9_wiggler(struct atmel_spi	*as)
{
  int ii;
  
  at91_set_gpio_output(AT91_PIN_PB1, 1);//data line
  at91_set_gpio_output(AT91_PIN_PB1, 0);//pull up off
  at91_set_gpio_output(AT91_PIN_PB2, 1);
  //at91_set_gpio_output(AT91_PIN_PB3, 1); we always own this pin
  
  SPI_DATA_HI;
  SPI_CLOCK_HI;
  SPI_RESET_ON; 
  SPI_RESET_OFF;
  SPI_RESET_ON; 
  SPI_RESET_OFF;
  
  for(ii = 0 ; ii < 12   ; ii++)
  {
    SPI_CLOCK_HI;
    SPI_CLOCK_LO;
  }
  SPI_DATA_HI;
  SPI_DATA_LO;
  for(ii = 12 ; ii < 16   ; ii++)
  {
    SPI_CLOCK_HI;
    SPI_CLOCK_LO;
  }
  at91_set_A_periph(AT91_PIN_PB2, 0);
  at91_set_A_periph(AT91_PIN_PB1, 0);//return data line to spi
  as->midi9spi.resync_flag = 0;
}
#else

// prime the counter by prerunning the clock
void midi9_wiggler(struct atmel_spi	*as)
{
  int ii;
  //at91_set_gpio_value(AT91_PIN_PC9, 1); this is a viewing pin see green line in scope shot hardware/pinaomation2/garpics_photos/midi9_wiggler_spi_reset.bmp
  
  at91_set_gpio_output(AT91_PIN_PB1, 1);//data line
  at91_set_gpio_output(AT91_PIN_PB1, 0);//pull up off
  at91_set_gpio_output(AT91_PIN_PB2, 1);
  
  at91_set_gpio_value( AT91_PIN_PB2, 1);
  at91_set_gpio_value( AT91_PIN_PB3, 0);
  at91_set_gpio_value( AT91_PIN_PB3, 1);
  at91_set_gpio_value( AT91_PIN_PB3, 0);
  at91_set_gpio_value( AT91_PIN_PB3, 1);
  for(ii = 0 ; ii < 16   ; ii++)
  {
    at91_set_gpio_value(AT91_PIN_PB2, 1);
    at91_set_gpio_value(AT91_PIN_PB2, 0);
  }
  at91_set_A_periph(AT91_PIN_PB2, 0);
  at91_set_A_periph(AT91_PIN_PB1, 0);//return data line to spi
  as->midi9spi.resync_flag = 0;
  //at91_set_gpio_value(AT91_PIN_PC9, 0);
  //printk("[%s]ips:%d words:%d bytes:%d\n",__FUNCTION__,as->midi9spi.instructions_per_sample,as->midi9spi.buffer_size_words, as->midi9spi.buffer_size_bytes);
}
#endif

static void midi9_setup_clock(struct atmel_spi	*as)
{
  int ii;
  int csr          = spi_readl(as, CSR0);
  u32 csr_invclock = csr | SPI_BIT(CPOL);//forces clock polarity high
  
  csr &= 0xffff00ff;//mask off clock divisor
  csr |= as->midi9spi.new_spi_divisor << 8;
  
  as->midi9spi.runtime_spi_divisor     = as->midi9spi.new_spi_divisor;
  as->midi9spi.instructions_per_sample = MAX_INSTRUCTIONS_PER_SAMPLE / as->midi9spi.runtime_spi_divisor;
  as->midi9spi.buffer_size_words       = as->midi9spi.instructions_per_sample * SAMPLES_PER_BUFFER;
  as->midi9spi.buffer_size_bytes       = as->midi9spi.buffer_size_words * BYTES_PER_INSTRUCTION;
  as->midi9spi.new_spi_divisor         = 0;
  for(ii = 0 ; ii < MAX_INSTRUCTIONS_PER_SAMPLE ; ii++)
     as->midi9spi.instruction[ii] = INACTIVE;
  dma_buffer_pwm_on(&as->midi9spi);
  as->midi9spi.new_data_in_buffer = 1;
  //midi9_wiggler(as);
  spi_writel(as, CSR0, csr);
  
  // prime the counter by prerunning the clock
  for(ii = 0 ; ii < 15 ; ii++)
  {
    spi_writel(as, CSR0, csr);
    spi_writel(as, CSR0, csr_invclock);
  }
  spi_writel(as, CSR0, csr);
  // Start clock
  //printk("[%s]ips:%d words:%d bytes:%d\n",__FUNCTION__,as->midi9spi.instructions_per_sample,as->midi9spi.buffer_size_words, as->midi9spi.buffer_size_bytes);
}

static void midi9_start_buffer(struct atmel_spi *as, dma_addr_t tx_dma, unsigned long len)
{
  unsigned long flags;

  spin_lock_irqsave(&as->lock, flags);
  spi_writel(as, RPR, tx_dma);              // Receive Pointer Register
  spi_writel(as, RNCR, 0);                  // Recieve Next Counter Register
  spi_writel(as, RCR,  0);                  // Receive Counter Register
  if (SAMPLE_BUFFERS_PER_IRQ == 2)
  {
    spi_writel(as, TNPR, tx_dma);           // Transmit Next Pointer Register
    spi_writel(as, TNCR, len);              // Transmit Next Counter Register
  }
  spi_writel(as, TPR, tx_dma);              // Transmit Pointer Register
  spi_writel(as, TCR, len);                 // Transmit Counter Register
  spi_writel(as, TNPR, tx_dma);             // Transmit Next Pointer Register
  spi_writel(as, TNCR, len);                // Transmit NextCounter Register
  spi_writel(as, IER, SPI_BIT(ENDTX));      // Interrupt Enable Register
  spi_writel(as, PTCR, SPI_BIT(TXTEN));     // Transmit Enable
  spin_unlock_irqrestore(&as->lock, flags);
}

static inline void midi9_update_pwm_buffer(struct atmel_spi *as)
{
  unsigned char *src  = (unsigned char *)as->midi9spi.buffer;
  unsigned char *dest = (unsigned char *)as->midi9spi.buffer + MAX_SAMPLE_BUFFER_SIZE_BYTES;//always in same place
  struct timeval timestamp;
  
 //at91_set_gpio_value(AT91_PIN_PC4, 1);
  if(as->midi9spi.resync_flag || (!(as->midi9spi.resync_counter++ & 0x0ff)))//reve 11 boards have a much higher propensity to misfire increase reset rate by 16
    midi9_wiggler(as);
  
  if(as->midi9spi.new_spi_divisor)
  {
     midi9_setup_clock(as);
  }   
  if (as->midi9spi.new_data_in_buffer)//this take 1.4 usec when data in buffer
  {
    memcpy(dest,src,32);//8 works 32 for saftey...
  }
  spi_writel(as, TNPR, SAMPLE_BUFFER_1_PHYS_ADDR);               // Transmit Next Pointer Register
  spi_writel(as, TNCR, as->midi9spi.buffer_size_words);          // Transmit Next Counter Register
  if (as->midi9spi.new_data_in_buffer)//this take 48 usec when data in buffer
  {
     memcpy(dest,src,as->midi9spi.buffer_size_bytes);
     as->midi9spi.new_data_in_buffer  = 0;
  }
  do_gettimeofday(&timestamp);
  midi9_midi_to_pwm_isr(&as->midi9spi, timestamp);//do this before starting buffer or partial xmits occur
 //at91_set_gpio_value(AT91_PIN_PC4, 0);
}

static int midi9_setup(struct spi_device *spi, struct atmel_spi	*as, int csr)
{
  int ii;
  u32 csr_invclock = csr | SPI_BIT(CPOL);//forces clock polarity high
    
  dma_buffer_init(&as->midi9spi);
  as->midi9spi.new_data_in_buffer = 1;
  
  // Start the buffer
  for (ii = 0; ii < as->midi9spi.instructions_per_sample; ii++)
    as->midi9spi.instruction[ii] = INACTIVE;
  
  cs_deactivate(as, spi);
  udelay(1);
  cs_activate(as, spi);
  
  // prime the counter by prerunning the clock
  for(ii = 0 ; ii < 15 ; ii++)
  {
    spi_writel(as, CSR0 + 4 * spi->chip_select, csr);
    spi_writel(as, CSR0 + 4 * spi->chip_select, csr_invclock);
  }
  // Start clock
  spi_writel(as, CSR0 + 4 * spi->chip_select, csr);
  midi9_start_buffer(as, SAMPLE_BUFFER_0_PHYS_ADDR, as->midi9spi.buffer_size_words);
  //at91_set_A_periph(AT91_PIN_PC4, 0);//used for debugging this sets the pin as an output without pullup
  //at91_set_gpio_output(AT91_PIN_PC4, 1);//used for debugging this sets the pin as an output without pullup
  //at91_set_gpio_output(AT91_PIN_PC7, 1);//used for debugging timing of ami
  //at91_set_gpio_value( AT91_PIN_PC7, 0);
  
  return 0;
}


static inline int atmel_spi_xfer_is_last(struct spi_message *msg,
					struct spi_transfer *xfer)
{
	return msg->transfers.prev == &xfer->transfer_list;
}

static inline int atmel_spi_xfer_can_be_chained(struct spi_transfer *xfer)
{
	return xfer->delay_usecs == 0 && !xfer->cs_change;
}

static void atmel_spi_next_xfer_data(struct spi_master *master,
				struct spi_transfer *xfer,
				dma_addr_t *tx_dma,
				dma_addr_t *rx_dma,
				u32 *plen)
{
	struct atmel_spi	*as = spi_master_get_devdata(master);
	u32			len = *plen;

	/* use scratch buffer only when rx or tx data is unspecified */
	if (xfer->rx_buf)
		*rx_dma = xfer->rx_dma + xfer->len - *plen;
	else {
		*rx_dma = as->buffer_dma;
		if (len > BUFFER_SIZE)
			len = BUFFER_SIZE;
	}
	if (xfer->tx_buf)
		*tx_dma = xfer->tx_dma + xfer->len - *plen;
	else {
		*tx_dma = as->buffer_dma;
		if (len > BUFFER_SIZE)
			len = BUFFER_SIZE;
		memset(as->buffer, 0, len);
		dma_sync_single_for_device(&as->pdev->dev,
				as->buffer_dma, len, DMA_TO_DEVICE);
	}

	*plen = len;
}

/*
 * Submit next transfer for DMA.
 * lock is held, spi irq is blocked
 */
static void atmel_spi_next_xfer(struct spi_master *master,
				struct spi_message *msg)
{
	struct atmel_spi	*as = spi_master_get_devdata(master);
	struct spi_transfer	*xfer;
	u32			len, remaining;
	u32			ieval;
	dma_addr_t		tx_dma, rx_dma;

	if (!as->current_transfer)
		xfer = list_entry(msg->transfers.next,
				struct spi_transfer, transfer_list);
	else if (!as->next_transfer)
		xfer = list_entry(as->current_transfer->transfer_list.next,
				struct spi_transfer, transfer_list);
	else
		xfer = NULL;

	if (xfer) {
		spi_writel(as, PTCR, SPI_BIT(RXTDIS) | SPI_BIT(TXTDIS));

		len = xfer->len;
		atmel_spi_next_xfer_data(master, xfer, &tx_dma, &rx_dma, &len);
		remaining = xfer->len - len;

		spi_writel(as, RPR, rx_dma);
		spi_writel(as, TPR, tx_dma);

		if (msg->spi->bits_per_word > 8)
			len >>= 1;
		spi_writel(as, RCR, len);
		spi_writel(as, TCR, len);

		dev_dbg(&msg->spi->dev,
			"  start xfer %p: len %u tx %p/%08x rx %p/%08x\n",
			xfer, xfer->len, xfer->tx_buf, xfer->tx_dma,
			xfer->rx_buf, xfer->rx_dma);
	} else {
		xfer = as->next_transfer;
		remaining = as->next_remaining_bytes;
	}

	as->current_transfer = xfer;
	as->current_remaining_bytes = remaining;

	if (remaining > 0)
		len = remaining;
	else if (!atmel_spi_xfer_is_last(msg, xfer)
			&& atmel_spi_xfer_can_be_chained(xfer)) {
		xfer = list_entry(xfer->transfer_list.next,
				struct spi_transfer, transfer_list);
		len = xfer->len;
	} else
		xfer = NULL;

	as->next_transfer = xfer;

	if (xfer) {
		u32	total;

		total = len;
		atmel_spi_next_xfer_data(master, xfer, &tx_dma, &rx_dma, &len);
		as->next_remaining_bytes = total - len;

		spi_writel(as, RNPR, rx_dma);
		spi_writel(as, TNPR, tx_dma);

		if (msg->spi->bits_per_word > 8)
			len >>= 1;
		spi_writel(as, RNCR, len);
		spi_writel(as, TNCR, len);

		dev_dbg(&msg->spi->dev,
			"  next xfer %p: len %u tx %p/%08x rx %p/%08x\n",
			xfer, xfer->len, xfer->tx_buf, xfer->tx_dma,
			xfer->rx_buf, xfer->rx_dma);
		ieval = SPI_BIT(ENDRX) | SPI_BIT(OVRES);
	} else {
		spi_writel(as, RNCR, 0);
		spi_writel(as, TNCR, 0);
		ieval = SPI_BIT(RXBUFF) | SPI_BIT(ENDRX) | SPI_BIT(OVRES);
	}

	/* REVISIT: We're waiting for ENDRX before we start the next
	 * transfer because we need to handle some difficult timing
	 * issues otherwise. If we wait for ENDTX in one transfer and
	 * then starts waiting for ENDRX in the next, it's difficult
	 * to tell the difference between the ENDRX interrupt we're
	 * actually waiting for and the ENDRX interrupt of the
	 * previous transfer.
	 *
	 * It should be doable, though. Just not now...
	 */
	spi_writel(as, IER, ieval);
	spi_writel(as, PTCR, SPI_BIT(TXTEN) | SPI_BIT(RXTEN));
}

static void atmel_spi_next_message(struct spi_master *master)
{
	struct atmel_spi	*as = spi_master_get_devdata(master);
	struct spi_message	*msg;
	struct spi_device	*spi;

	BUG_ON(as->current_transfer);

	msg = list_entry(as->queue.next, struct spi_message, queue);
	spi = msg->spi;

	dev_dbg(master->dev.parent, "start message %p for %s\n",
			msg, dev_name(&spi->dev));

	/* select chip if it's not still active */
	if (as->stay) {
		if (as->stay != spi) {
			cs_deactivate(as, as->stay);
			cs_activate(as, spi);
		}
		as->stay = NULL;
	} else
		cs_activate(as, spi);

	atmel_spi_next_xfer(master, msg);
}

/*
 * For DMA, tx_buf/tx_dma have the same relationship as rx_buf/rx_dma:
 *  - The buffer is either valid for CPU access, else NULL
 *  - If the buffer is valid, so is its DMA addresss
 *
 * This driver manages the dma addresss unless message->is_dma_mapped.
 */
static int
atmel_spi_dma_map_xfer(struct atmel_spi *as, struct spi_transfer *xfer)
{
	struct device	*dev = &as->pdev->dev;

	xfer->tx_dma = xfer->rx_dma = INVALID_DMA_ADDRESS;
	if (xfer->tx_buf) {
		xfer->tx_dma = dma_map_single(dev,
				(void *) xfer->tx_buf, xfer->len,
				DMA_TO_DEVICE);
		if (dma_mapping_error(dev, xfer->tx_dma))
			return -ENOMEM;
	}
	if (xfer->rx_buf) {
		xfer->rx_dma = dma_map_single(dev,
				xfer->rx_buf, xfer->len,
				DMA_FROM_DEVICE);
		if (dma_mapping_error(dev, xfer->rx_dma)) {
			if (xfer->tx_buf)
				dma_unmap_single(dev,
						xfer->tx_dma, xfer->len,
						DMA_TO_DEVICE);
			return -ENOMEM;
		}
	}
	return 0;
}

static void atmel_spi_dma_unmap_xfer(struct spi_master *master,
				     struct spi_transfer *xfer)
{
	if (xfer->tx_dma != INVALID_DMA_ADDRESS)
		dma_unmap_single(master->dev.parent, xfer->tx_dma,
				 xfer->len, DMA_TO_DEVICE);
	if (xfer->rx_dma != INVALID_DMA_ADDRESS)
		dma_unmap_single(master->dev.parent, xfer->rx_dma,
				 xfer->len, DMA_FROM_DEVICE);
}

static void
atmel_spi_msg_done(struct spi_master *master, struct atmel_spi *as,
		struct spi_message *msg, int status, int stay)
{
	if (!stay || status < 0)
		cs_deactivate(as, msg->spi);
	else
		as->stay = msg->spi;

	list_del(&msg->queue);
	msg->status = status;

	dev_dbg(master->dev.parent,
		"xfer complete: %u bytes transferred\n",
		msg->actual_length);

	spin_unlock(&as->lock);
	msg->complete(msg->context);
	spin_lock(&as->lock);

	as->current_transfer = NULL;
	as->next_transfer = NULL;

	/* continue if needed */
	if (list_empty(&as->queue) || as->stopping)
		spi_writel(as, PTCR, SPI_BIT(RXTDIS) | SPI_BIT(TXTDIS));
	else
		atmel_spi_next_message(master);
}

static irqreturn_t
atmel_spi_interrupt(int irq, void *dev_id)
{
	struct spi_master	*master = dev_id;
	struct atmel_spi	*as = spi_master_get_devdata(master);
	struct spi_message	*msg;
	struct spi_transfer	*xfer;
	u32			status, pending, imr;
	int			ret = IRQ_NONE;

	spin_lock(&as->lock);

	xfer = as->current_transfer;
	msg = list_entry(as->queue.next, struct spi_message, queue);

	imr = spi_readl(as, IMR);
	status = spi_readl(as, SR);
	pending = status & imr;

	if (pending & SPI_BIT(OVRES)) {
		int timeout;

		ret = IRQ_HANDLED;

		spi_writel(as, IDR, (SPI_BIT(RXBUFF) | SPI_BIT(ENDRX)
				     | SPI_BIT(OVRES)));

		/*
		 * When we get an overrun, we disregard the current
		 * transfer. Data will not be copied back from any
		 * bounce buffer and msg->actual_len will not be
		 * updated with the last xfer.
		 *
		 * We will also not process any remaning transfers in
		 * the message.
		 *
		 * First, stop the transfer and unmap the DMA buffers.
		 */
		spi_writel(as, PTCR, SPI_BIT(RXTDIS) | SPI_BIT(TXTDIS));
		if (!msg->is_dma_mapped)
			atmel_spi_dma_unmap_xfer(master, xfer);

		/* REVISIT: udelay in irq is unfriendly */
		if (xfer->delay_usecs)
			udelay(xfer->delay_usecs);

		dev_warn(master->dev.parent, "overrun (%u/%u remaining)\n",
			 spi_readl(as, TCR), spi_readl(as, RCR));

		/*
		 * Clean up DMA registers and make sure the data
		 * registers are empty.
		 */
		spi_writel(as, RNCR, 0);
		spi_writel(as, TNCR, 0);
		spi_writel(as, RCR, 0);
		spi_writel(as, TCR, 0);
		for (timeout = 1000; timeout; timeout--)
			if (spi_readl(as, SR) & SPI_BIT(TXEMPTY))
				break;
		if (!timeout)
			dev_warn(master->dev.parent,
				 "timeout waiting for TXEMPTY");
		while (spi_readl(as, SR) & SPI_BIT(RDRF))
			spi_readl(as, RDR);

		/* Clear any overrun happening while cleaning up */
		spi_readl(as, SR);

		atmel_spi_msg_done(master, as, msg, -EIO, 0);
	} else if (pending & (SPI_BIT(RXBUFF) | SPI_BIT(ENDRX))) {
		ret = IRQ_HANDLED;

		spi_writel(as, IDR, pending);

		if (as->current_remaining_bytes == 0) {
			msg->actual_length += xfer->len;

			if (!msg->is_dma_mapped)
				atmel_spi_dma_unmap_xfer(master, xfer);

			/* REVISIT: udelay in irq is unfriendly */
			if (xfer->delay_usecs)
				udelay(xfer->delay_usecs);

			if (atmel_spi_xfer_is_last(msg, xfer)) {
				/* report completed message */
				atmel_spi_msg_done(master, as, msg, 0,
						xfer->cs_change);
			} else {
				if (xfer->cs_change) {
					cs_deactivate(as, msg->spi);
					udelay(1);
					cs_activate(as, msg->spi);
				}

				/*
				 * Not done yet. Submit the next transfer.
				 *
				 * FIXME handle protocol options for xfer
				 */
				atmel_spi_next_xfer(master, msg);
			}
		} else {
			/*
			 * Keep going, we still have data to send in
			 * the current transfer.
			 */
			atmel_spi_next_xfer(master, msg);
		}
	} else if (pending & SPI_BIT(ENDTX)) {         // } else if (pending & (SPI_BIT(TXBUFF) | SPI_BIT(ENDTX))) {
        ret = IRQ_HANDLED;
        midi9_update_pwm_buffer(as);
    }    

	spin_unlock(&as->lock);
	return ret;
}

static int atmel_spi_setup(struct spi_device *spi)
{
	struct atmel_spi	*as;
	struct atmel_spi_device	*asd;
	u32			scbr, csr;
	unsigned int		bits = spi->bits_per_word;
	unsigned long		bus_hz;
	unsigned int		npcs_pin;
	int			ret;

#ifdef MIDI9
    spi->max_speed_hz = SPI_MASTER_BPS / 2;//start at max then maybe bring it down>>??!! FIXIT think about it
    spi->mode = SPI_CS_HIGH;
    spi->bits_per_word = bits = 16;
#endif    

	as = spi_master_get_devdata(spi->master);

	if (as->stopping)
		return -ESHUTDOWN;

	if (spi->chip_select > spi->master->num_chipselect) {
		dev_dbg(&spi->dev,
				"setup: invalid chipselect %u (%u defined)\n",
				spi->chip_select, spi->master->num_chipselect);
		return -EINVAL;
	}

	if (bits < 8 || bits > 16) {
		dev_dbg(&spi->dev,
				"setup: invalid bits_per_word %u (8 to 16)\n",
				bits);
		return -EINVAL;
	}

	/* see notes above re chipselect */
	if (!atmel_spi_is_v2()
			&& spi->chip_select == 0
			&& (spi->mode & SPI_CS_HIGH)) {
		dev_dbg(&spi->dev, "setup: can't be active-high\n");
		return -EINVAL;
	}

	/* v1 chips start out at half the peripheral bus speed. */
	bus_hz = clk_get_rate(as->clk);
	if (!atmel_spi_is_v2())
		bus_hz /= 2;

	if (spi->max_speed_hz) {
		/*
		 * Calculate the lowest divider that satisfies the
		 * constraint, assuming div32/fdiv/mbz == 0.
		 */
		scbr = DIV_ROUND_UP(bus_hz, spi->max_speed_hz);

		/*
		 * If the resulting divider doesn't fit into the
		 * register bitfield, we can't satisfy the constraint.
		 */
		if (scbr >= (1 << SPI_SCBR_SIZE)) {
			dev_dbg(&spi->dev,
				"setup: %d Hz too slow, scbr %u; min %ld Hz\n",
				spi->max_speed_hz, scbr, bus_hz/255);
			return -EINVAL;
		}
	} else
		/* speed zero means "as slow as possible" */
		scbr = 0xff;

	csr = SPI_BF(SCBR, scbr) | SPI_BF(BITS, bits - 8);
	if (spi->mode & SPI_CPOL)
		csr |= SPI_BIT(CPOL);
	if (!(spi->mode & SPI_CPHA))
		csr |= SPI_BIT(NCPHA);

	/* DLYBS is mostly irrelevant since we manage chipselect using GPIOs.
	 *
	 * DLYBCT would add delays between words, slowing down transfers.
	 * It could potentially be useful to cope with DMA bottlenecks, but
	 * in those cases it's probably best to just use a lower bitrate.
	 */
	csr |= SPI_BF(DLYBS, 0);
	csr |= SPI_BF(DLYBCT, 0);

	/* chipselect must have been muxed as GPIO (e.g. in board setup) */
	npcs_pin = (unsigned int)spi->controller_data;
	asd = spi->controller_state;
	if (!asd) {
		asd = kzalloc(sizeof(struct atmel_spi_device), GFP_KERNEL);
		if (!asd)
			return -ENOMEM;

		ret = gpio_request(npcs_pin, dev_name(&spi->dev));
		if (ret) {
			kfree(asd);
			return ret;
		}

		asd->npcs_pin = npcs_pin;
		spi->controller_state = asd;
		gpio_direction_output(npcs_pin, !(spi->mode & SPI_CS_HIGH));
	} else {
		unsigned long		flags;

		spin_lock_irqsave(&as->lock, flags);
		if (as->stay == spi)
			as->stay = NULL;
		cs_deactivate(as, spi);
		spin_unlock_irqrestore(&as->lock, flags);
	}

	asd->csr = csr;

	dev_dbg(&spi->dev,
		"setup: %lu Hz bpw %u mode 0x%x -> csr%d %08x\n",
		bus_hz / scbr, bits, spi->mode, spi->chip_select, csr);

    //printk("[%s]: PWM: %d Hz (%ld uS), IRQ time %ld uS\n", __FUNCTION__, PWM_HZ, PWM_TIME_US, IRQ_TIME_US);

	if (!atmel_spi_is_v2())
		spi_writel(as, CSR0 + 4 * spi->chip_select, csr);

  midi9_setup(spi, as, csr);
	return 0;
}

static int atmel_spi_transfer(struct spi_device *spi, struct spi_message *msg)
{
	struct atmel_spi	*as;
	struct spi_transfer	*xfer;
	unsigned long		flags;
	struct device		*controller = spi->master->dev.parent;

	as = spi_master_get_devdata(spi->master);

	dev_dbg(controller, "new message %p submitted for %s\n",
			msg, dev_name(&spi->dev));

	if (unlikely(list_empty(&msg->transfers)))
		return -EINVAL;

	if (as->stopping)
		return -ESHUTDOWN;

	list_for_each_entry(xfer, &msg->transfers, transfer_list) {
		if (!(xfer->tx_buf || xfer->rx_buf) && xfer->len) {
			dev_dbg(&spi->dev, "missing rx or tx buf\n");
			return -EINVAL;
		}

		/* FIXME implement these protocol options!! */
		if (xfer->bits_per_word || xfer->speed_hz) {
			dev_dbg(&spi->dev, "no protocol options yet\n");
			return -ENOPROTOOPT;
		}

		/*
		 * DMA map early, for performance (empties dcache ASAP) and
		 * better fault reporting.  This is a DMA-only driver.
		 *
		 * NOTE that if dma_unmap_single() ever starts to do work on
		 * platforms supported by this driver, we would need to clean
		 * up mappings for previously-mapped transfers.
		 */
		if (!msg->is_dma_mapped) {
			if (atmel_spi_dma_map_xfer(as, xfer) < 0)
				return -ENOMEM;
		}
	}

#ifdef VERBOSE
	list_for_each_entry(xfer, &msg->transfers, transfer_list) {
		dev_dbg(controller,
			"  xfer %p: len %u tx %p/%08x rx %p/%08x\n",
			xfer, xfer->len,
			xfer->tx_buf, xfer->tx_dma,
			xfer->rx_buf, xfer->rx_dma);
	}
#endif

	msg->status = -EINPROGRESS;
	msg->actual_length = 0;

	spin_lock_irqsave(&as->lock, flags);
	list_add_tail(&msg->queue, &as->queue);
	if (!as->current_transfer)
		atmel_spi_next_message(spi->master);
	spin_unlock_irqrestore(&as->lock, flags);

	return 0;
}

static void atmel_spi_cleanup(struct spi_device *spi)
{
	struct atmel_spi	*as = spi_master_get_devdata(spi->master);
	struct atmel_spi_device	*asd = spi->controller_state;
	unsigned		gpio = (unsigned) spi->controller_data;
	unsigned long		flags;

	if (!asd)
		return;

	spin_lock_irqsave(&as->lock, flags);
	if (as->stay == spi) {
		as->stay = NULL;
		cs_deactivate(as, spi);
	}
	spin_unlock_irqrestore(&as->lock, flags);

	spi->controller_state = NULL;
	gpio_free(gpio);
	kfree(asd);
}

/*-------------------------------------------------------------------------*/

static int __init atmel_spi_probe(struct platform_device *pdev)
{
	struct resource		*regs;
	int			irq;
	struct clk		*clk;
	int			ret;
	struct spi_master	*master;
	struct atmel_spi	*as;
#ifdef MIDI9
    struct resource *dma_buffer;

    dma_buffer = platform_get_resource(pdev, IORESOURCE_MEM, 2);
    if (!dma_buffer) {
        printk("[%s]: DMA buffer memory allocation failed\n", __FUNCTION__);
        return -ENXIO;
    }
#endif    
	regs = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!regs)
		return -ENXIO;
    
	irq = platform_get_irq(pdev, 0);
	if (irq < 0)
		return irq;

	clk = clk_get(&pdev->dev, "spi1_clk");
	if (IS_ERR(clk))
		return PTR_ERR(clk);

	/* setup spi core then atmel-specific driver state */
	ret = -ENOMEM;
	master = spi_alloc_master(&pdev->dev, sizeof *as);
	if (!master)
		goto out_free;

	/* the spi->mode bits understood by this driver: */
	master->mode_bits = SPI_CPOL | SPI_CPHA | SPI_CS_HIGH;

	master->bus_num = pdev->id;
	master->num_chipselect = 4;
	master->setup = atmel_spi_setup;
	master->transfer = atmel_spi_transfer;
	master->cleanup = atmel_spi_cleanup;
	platform_set_drvdata(pdev, master);

	as = spi_master_get_devdata(master);
  set_atmel_spi_atmel_spi(as);

	/*
	 * Scratch buffer is used for throwaway rx and tx data.
	 * It's coherent to minimize dcache pollution.
	 */
	as->buffer = dma_alloc_coherent(&pdev->dev, BUFFER_SIZE,
					&as->buffer_dma, GFP_KERNEL);
	if (!as->buffer)
		goto out_free;
  as->midi9spi.runtime_spi_divisor = DEFAULT_SPI_DIVISOR;
  as->midi9spi.resync_flag    = 0;
  as->midi9spi.resync_counter = 0;
  as->midi9spi.instructions_per_sample = MAX_INSTRUCTIONS_PER_SAMPLE / as->midi9spi.runtime_spi_divisor;
  as->midi9spi.new_spi_divisor = 0;
  as->midi9spi.buffer_size_words =  (MAX_INSTRUCTIONS_PER_SAMPLE * SAMPLES_PER_BUFFER) / as->midi9spi.runtime_spi_divisor;
  as->midi9spi.buffer_size_bytes =  as->midi9spi.buffer_size_words * BYTES_PER_INSTRUCTION;

	spin_lock_init(&as->lock);
	INIT_LIST_HEAD(&as->queue);
	as->pdev = pdev;
	as->regs = ioremap(regs->start, resource_size(regs));
	if (!as->regs)
		goto out_free_buffer;
        
#ifdef MIDI9
    as->midi9spi.buffer = ioremap(dma_buffer->start, (dma_buffer->end - dma_buffer->start) + 1);
    if (!as->midi9spi.buffer) {
        printk("[%s]: DMA buffer remap failed\n", __FUNCTION__);
        return ret;
    }
    as->midi9spi.new_data_in_buffer = 1;
#endif    
        
	as->irq = irq;
	as->clk = clk;

	ret = request_irq(irq, atmel_spi_interrupt, 0,
			dev_name(&pdev->dev), master);
	if (ret)
		goto out_unmap_regs;

	/* Initialize the hardware */
	clk_enable(clk);
	spi_writel(as, CR, SPI_BIT(SWRST));
	spi_writel(as, CR, SPI_BIT(SWRST)); /* AT91SAM9263 Rev B workaround */
#ifdef MIDI9
    spi_writel(as, MR, SPI_BF(DLYBCS, 0) | SPI_BIT(MSTR) | SPI_BIT(MODFDIS));
#else  
	spi_writel(as, MR, SPI_BIT(MSTR) | SPI_BIT(MODFDIS));
#endif    
    
	spi_writel(as, PTCR, SPI_BIT(RXTDIS) | SPI_BIT(TXTDIS));
	spi_writel(as, CR, SPI_BIT(SPIEN));

	/* go! */
//	dev_info(&pdev->dev, "Atmel SPI Controller at 0x%08lx (irq %d)\n",
//			(unsigned long)regs->start, irq);

	ret = spi_register_master(master);
	if (ret)
		goto out_reset_hw;

	return 0;

out_reset_hw:
	spi_writel(as, CR, SPI_BIT(SWRST));
	spi_writel(as, CR, SPI_BIT(SWRST)); /* AT91SAM9263 Rev B workaround */
	clk_disable(clk);
	free_irq(irq, master);
out_unmap_regs:
	iounmap(as->regs);
out_free_buffer:
	dma_free_coherent(&pdev->dev, BUFFER_SIZE, as->buffer,
			as->buffer_dma);
out_free:
	clk_put(clk);
	spi_master_put(master);
	return ret;
}

static int __exit atmel_spi_remove(struct platform_device *pdev)
{
	struct spi_master	*master = platform_get_drvdata(pdev);
	struct atmel_spi	*as = spi_master_get_devdata(master);
	struct spi_message	*msg;

	/* reset the hardware and block queue progress */
	spin_lock_irq(&as->lock);
	as->stopping = 1;
	spi_writel(as, CR, SPI_BIT(SWRST));
	spi_writel(as, CR, SPI_BIT(SWRST)); /* AT91SAM9263 Rev B workaround */
	spi_readl(as, SR);
	spin_unlock_irq(&as->lock);

	/* Terminate remaining queued transfers */
	list_for_each_entry(msg, &as->queue, queue) {
		/* REVISIT unmapping the dma is a NOP on ARM and AVR32
		 * but we shouldn't depend on that...
		 */
		msg->status = -ESHUTDOWN;
		msg->complete(msg->context);
	}

	dma_free_coherent(&pdev->dev, BUFFER_SIZE, as->buffer,
			as->buffer_dma);

	clk_disable(as->clk);
	clk_put(as->clk);
	free_irq(as->irq, master);
	iounmap(as->midi9spi.buffer);
	iounmap(as->regs);

	spi_unregister_master(master);

	return 0;
}

#ifdef	CONFIG_PM

static int atmel_spi_suspend(struct platform_device *pdev, pm_message_t mesg)
{
	struct spi_master	*master = platform_get_drvdata(pdev);
	struct atmel_spi	*as = spi_master_get_devdata(master);

	clk_disable(as->clk);
	return 0;
}

static int atmel_spi_resume(struct platform_device *pdev)
{
	struct spi_master	*master = platform_get_drvdata(pdev);
	struct atmel_spi	*as = spi_master_get_devdata(master);

	clk_enable(as->clk);
	return 0;
}

#else
#define	atmel_spi_suspend	NULL
#define	atmel_spi_resume	NULL
#endif


// NOTE!!!!: Must .name must match value in at91sam9260devices.c
static struct platform_driver atmel_spi_driver = {
	.driver		= {
		.name	= "snd_spi_pwm_midi",
		.owner	= THIS_MODULE,
	},
	.suspend	= atmel_spi_suspend,
	.resume		= atmel_spi_resume,
	.remove		= __exit_p(atmel_spi_remove),
};

int __init midi9_spi_init(void)
{
	return platform_driver_probe(&atmel_spi_driver, atmel_spi_probe);
}

void __exit midi9_spi_exit(void)
{
  platform_driver_unregister(&atmel_spi_driver);
}

void  midi9_spi_resume(void *as_in)
{
	struct atmel_spi	*as = as_in;
  
	as->midi9spi.resync_flag = 1;
  clk_enable(as->clk);
  return;
}
