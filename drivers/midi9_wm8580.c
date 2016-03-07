/* 
 *             _     _ _  ___  
 *   _ __ ___ (_) __| (_)/ _ \ 
 *  | '_ ` _ \| |/ _` | | (_) |
 *  | | | | | | | (_| | |\__, |
 *  |_| |_| |_|_|\__,_|_|  /_/ 
 *
 */
/**
 * @file    midi9_wm8580.c
 * @brief   SoC audio for AT91SAM9G20-based
 */ 
#include <linux/module.h>
#include <sound/soc.h>
#include <sound/pcm_params.h>

#include <asm/mach-types.h>

#include <linux/i2c.h>
#include "../codecs/wm8580.h"

#include "atmel_ssc_dai.h"

/*----------------------------------------------------------------------------*\
 * Defines
\*----------------------------------------------------------------------------*/
#define MIDI9_WM8580_FREQ 12000000

#define DEFAULT_SAMPLE_RATE 44100
/* empirical. FIXIT, find value */
#define CODEC_FREQUENCY_MIN  35000
#define CODEC_FREQUENCY_MAX  50000

/*----------------------------------------------------------------------------*\
 * global variables
\*----------------------------------------------------------------------------*/
//static struct clk *mclk;
static struct platform_device *midi9_snd_device;

/*----------------------------------------------------------------------------*\
 * exported functions - sample rate, very hacky
\*----------------------------------------------------------------------------*/
static int g_sample_rate;
extern void midi9_set_codec_sample_rate(int sample_rate);
void midi9_set_sample_rate(int sample_rate)
{
  g_sample_rate = sample_rate;
  midi9_set_codec_sample_rate(sample_rate);
}
EXPORT_SYMBOL(midi9_set_sample_rate);

/*----------------------------------------------------------------------------*\
 * driver functions
\*----------------------------------------------------------------------------*/
static int midi9_hw_params(struct snd_pcm_substream *substream, struct snd_pcm_hw_params *params)
{
  struct snd_soc_pcm_runtime *rtd = substream->private_data;
  struct snd_soc_dai *cpu_dai = rtd->cpu_dai;
  struct snd_soc_dai *codec_dai = rtd->codec_dai;
  unsigned int pll_out;
  int rfs, ret;

  /* The Fvco for WM8580 PLLs must fall within [90,100]MHz.
   * This criterion can't be met if we request PLL output
   * as {8000x256, 64000x256, 11025x256}Hz.
   * As a wayout, we rather change rfs to a minimum value that
   * results in (params_rate(params) * rfs), and itself, acceptable
   * to both - the CODEC and the CPU.
   */
  switch (params_rate(params)) {
  case 16000:
  case 22050:
  case 32000:
  case 44100:
  case 48000:
  case 88200:
  case 96000:
    rfs = 256;
    break;
  case 64000:
    rfs = 384;
    break;
  case 8000:
  case 11025:
    rfs = 512;
    break;
  default:
    return -EINVAL;
  }
  if ((g_sample_rate >= CODEC_FREQUENCY_MIN) && (g_sample_rate <= CODEC_FREQUENCY_MAX))
  {
    pll_out = g_sample_rate * rfs;
  }
  else
  {
    printk("[%s]: Invalid sample %d, set to %d Hz\n", __FUNCTION__, g_sample_rate, DEFAULT_SAMPLE_RATE);
    g_sample_rate = DEFAULT_SAMPLE_RATE;
  }
  pll_out = g_sample_rate * rfs;

  /* Set the AP DAI configuration */
  ret = snd_soc_dai_set_fmt(cpu_dai, SND_SOC_DAIFMT_I2S
           | SND_SOC_DAIFMT_NB_NF
           | SND_SOC_DAIFMT_CBM_CFM);
  if (ret < 0)
    return ret;

  /* Set the Codec DAI configuration */
  if (codec_dai->id == WM8580_DAI_PAIFRX)
  {
    ret = snd_soc_dai_set_fmt(codec_dai, SND_SOC_DAIFMT_DSP_A
             | SND_SOC_DAIFMT_NB_NF
             | SND_SOC_DAIFMT_CBM_CFM);
    if (ret < 0)
      return ret;
  }
  if (codec_dai->id == WM8580_DAI_PAIFTX)
  {
    ret = snd_soc_dai_set_fmt(codec_dai, SND_SOC_DAIFMT_DSP_A
             | SND_SOC_DAIFMT_NB_NF
             | SND_SOC_DAIFMT_CBS_CFS);
    if (ret < 0)
      return ret;
  }

  /* PLLA ---> Clock Out */
  ret = snd_soc_dai_set_clkdiv(codec_dai, WM8580_CLKOUTSRC, WM8580_CLKSRC_PLLA);
  if (ret < 0)
    return ret;
  /* Clock Out --> MCLK */
  ret = snd_soc_dai_set_clkdiv(codec_dai, WM8580_MCLK, WM8580_CLKSRC_MCLK);
  if (ret < 0)
    return ret;
  /* PLLA --> DAC Clock */
  if (codec_dai->id == WM8580_DAI_PAIFRX)
  {
    ret = snd_soc_dai_set_clkdiv(codec_dai, WM8580_DAC_CLKSEL, WM8580_CLKSRC_PLLA);
    if (ret < 0)
      return ret;
  }
  /* PLLA -> ADC Clock */
  if (codec_dai->id == WM8580_DAI_PAIFTX)
  {
    ret = snd_soc_dai_set_clkdiv(codec_dai, WM8580_ADC_CLKSEL, WM8580_CLKSRC_PLLA);
    if (ret < 0) 
      return ret;
  }
  ret = snd_soc_dai_set_pll(codec_dai, WM8580_PLLA, 0,
          MIDI9_WM8580_FREQ, pll_out);
  if (ret < 0)
    return ret;

  ret = snd_soc_dai_set_sysclk(codec_dai, WM8580_CLKSRC_PLLA,
          pll_out, SND_SOC_CLOCK_IN);
  if (ret < 0)
    return ret;

  return 0;
}

/*
 * MIDI9 WM8580 DAI operations.
 */
static struct snd_soc_ops midi9_ops = {
  .hw_params = midi9_hw_params,
};

/* MIDI9 Playback widgets */
static const struct snd_soc_dapm_widget wm8580_dapm_widgets_pbk[] = {
  SND_SOC_DAPM_HP("Front", NULL),
  SND_SOC_DAPM_HP("Center+Sub", NULL),
  SND_SOC_DAPM_HP("Rear", NULL),
};

/* MIDI9 Capture widgets */
static const struct snd_soc_dapm_widget wm8580_dapm_widgets_cpt[] = {
  SND_SOC_DAPM_MIC("MicIn", NULL),
  SND_SOC_DAPM_LINE("LineIn", NULL),
};

/* MIDI9-PAIFTX connections */
static const struct snd_soc_dapm_route audio_map_tx[] = {
  /* MicIn feeds AINL */
  {"AINL", NULL, "MicIn"},

  /* LineIn feeds AINL/R */
  {"AINL", NULL, "LineIn"},
  {"AINR", NULL, "LineIn"},
};

/* MIDI9-PAIFRX connections */
static const struct snd_soc_dapm_route audio_map_rx[] = {
  /* Front Left/Right are fed VOUT1L/R */
  {"Front", NULL, "VOUT1L"},
  {"Front", NULL, "VOUT1R"},

  /* Center/Sub are fed VOUT2L/R */
  {"Center+Sub", NULL, "VOUT2L"},
  {"Center+Sub", NULL, "VOUT2R"},

  /* Rear Left/Right are fed VOUT3L/R */
  {"Rear", NULL, "VOUT3L"},
  {"Rear", NULL, "VOUT3R"},
};

static int midi9_wm8580_init_paiftx(struct snd_soc_pcm_runtime *rtd)
{
  struct snd_soc_codec *codec = rtd->codec;
  struct snd_soc_dapm_context *dapm = &codec->dapm;

  /* Add midi9 specific Capture widgets */
  snd_soc_dapm_new_controls(dapm, wm8580_dapm_widgets_cpt,
          ARRAY_SIZE(wm8580_dapm_widgets_cpt));

  /* Set up PAIFTX audio path */
  snd_soc_dapm_add_routes(dapm, audio_map_tx, ARRAY_SIZE(audio_map_tx));

  /* signal a DAPM event */
  snd_soc_dapm_sync(dapm);

  return 0;
}

static int midi9_wm8580_init_paifrx(struct snd_soc_pcm_runtime *rtd)
{
  struct snd_soc_codec *codec = rtd->codec;
  struct snd_soc_dapm_context *dapm = &codec->dapm;

  /* Add midi9 specific Playback widgets */
  snd_soc_dapm_new_controls(dapm, wm8580_dapm_widgets_pbk, ARRAY_SIZE(wm8580_dapm_widgets_pbk));

  /* Set up PAIFRX audio path */
  snd_soc_dapm_add_routes(dapm, audio_map_rx, ARRAY_SIZE(audio_map_rx));

  /* signal a DAPM event */
  snd_soc_dapm_sync(dapm);

  return 0;
}

enum {
  PRI_PLAYBACK = 0,
  PRI_CAPTURE,
  SEC_PLAYBACK,
};

static struct snd_soc_dai_link midi9_dai[] = {
  [PRI_PLAYBACK] = { /* Primary Playback i/f */
    .name = "WM8580 PAIF RX",
    .stream_name = "Playback",
    .cpu_dai_name = "atmel-ssc-dai.0",
    .codec_dai_name = "wm8580-hifi-playback",
    .platform_name = "atmel-pcm-audio",
    .codec_name = "wm8580-codec.0-001a",
    .init = midi9_wm8580_init_paifrx,
    .ops = &midi9_ops,
  },
  [PRI_CAPTURE] = { /* Primary Capture i/f */
    .name = "WM8580 PAIF TX",
    .stream_name = "Capture",
    .cpu_dai_name = "atmel-ssc-dai.0",
    .codec_dai_name = "wm8580-hifi-capture",
    .platform_name = "atmel-pcm-audio",
    .codec_name = "wm8580-codec.0-001a",
    .init = midi9_wm8580_init_paiftx,
    .ops = &midi9_ops,
  },
  [SEC_PLAYBACK] = { /* Sec_Fifo Playback i/f */
    .name = "Sec_FIFO TX",
    .stream_name = "Playback",
    .cpu_dai_name = "atmel-ssc-dai.x",
    .codec_dai_name = "wm8580-hifi-playback",
    .platform_name = "atmel-pcm-audio",
    .codec_name = "wm8580-codec.0-001a",
    .init = midi9_wm8580_init_paifrx,
    .ops = &midi9_ops,
  },
};

static struct snd_soc_card midi9 = {
  .name = "MIDI9_PCM",
  .dai_link = midi9_dai,
  .num_links = 2,
};

static struct i2c_board_info i2c_device[] = {
  { I2C_BOARD_INFO("wm8580", 0x1a), }
};

static int __init midi9_wm8580_init(void)
{
  int ret;
  struct i2c_adapter *adapter;
  struct i2c_client *client;

  if (!(machine_is_at91sam9g20ek() || machine_is_at91sam9g20ek_2mmc()))
    return -ENODEV;
  adapter = i2c_get_adapter(0);
  if (!adapter) {
    printk("[%s]: Can't get i2c adaptor\n", __FUNCTION__);
    return -ENODEV;
  }    
  client = i2c_new_device(adapter, i2c_device);
  i2c_put_adapter(adapter);
  if (!client) {
    printk("[%s]: Can't add i2c device\n", __FUNCTION__);
    return -ENODEV;
  }
#if 0
  /*
   * Codec MCLK is supplied by PCK0 - set it up.
   */
  mclk = clk_get(NULL, "pck0");
  if (IS_ERR(mclk)) {
    printk(KERN_ERR "ASoC: Failed to get MCLK\n");
    ret = PTR_ERR(mclk);
    goto err;
  }
  clk_set_rate(mclk, MIDI9_WM8580_FREQ/2);
#endif

  ret = atmel_ssc_set_audio(0);
  if (ret != 0) {
    printk("Failed to set SSC 0 for audio: %d\n", ret);
    goto err_ssc;
  }

  midi9_snd_device = platform_device_alloc("soc-audio", -1);
  if (!midi9_snd_device) {
    printk(KERN_ERR "ASoC: Platform device allocation failed\n");
    ret = -ENOMEM;
    goto err_ssc;
  }

  platform_set_drvdata(midi9_snd_device,
      &midi9);

  ret = platform_device_add(midi9_snd_device);
  if (ret) {
    printk(KERN_ERR "ASoC: Platform device allocation failed\n");
    goto err_device_add;
  }
  g_sample_rate = DEFAULT_SAMPLE_RATE;
  return ret;

err_device_add:
  platform_device_put(midi9_snd_device);
err_ssc:
//  clk_put(mclk);
//  mclk = NULL;
//err:
  return ret;
}

static void __exit midi9_wm8580_exit(void)
{
  platform_device_unregister(midi9_snd_device);
  midi9_snd_device = NULL;
//  clk_put(mclk);
//  mclk = NULL;
}

module_init(midi9_wm8580_init);
module_exit(midi9_wm8580_exit);

/* Module information */
MODULE_AUTHOR("Anthony Sarain <anthony@sarain.com>");
MODULE_DESCRIPTION("ALSA SoC midi9_WM8580");
MODULE_LICENSE("GPL");
