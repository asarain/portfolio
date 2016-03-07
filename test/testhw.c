/*
 *             _     _ _  ___  
 *   _ __ ___ (_) __| (_)/ _ \ 
 *  | '_ ` _ \| |/ _` | | (_) |
 *  | | | | | | | (_| | |\__, |
 *  |_| |_| |_|_|\__,_|_|  /_/ 
 *    
 *
 */
/**
 * @file    testhw.c
 * @brief   HW test program
 */ 
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <termios.h>
#include <poll.h>
#include <sys/time.h>
#include <sys/signal.h>
#include <sys/time.h>
#include <linux/input.h>
#include <math.h>
#include <limits.h>
#include <errno.h>
#include <syslog.h>

#include "common/src/pm2_time.h"
#include "common/src/pm2_ipc.h"

#include "common/midi9_versions.h"
#include "common/midi9_filenames.h"
#include "common/midi9_util.h"
#include "common/midi9_mainloop.h"
#include "common/midi9_alsa.h"
#include "common/midi9_debug.h"


#include "midi9lib.h"
#include "common/midi9_apps.h"
#include "ppu/ppu.h"

#include "midi9d/midi9d.h"

/*--------------------------------------------------------------------------*\
 * Defines
\*--------------------------------------------------------------------------*/
static int button_device_handler(void *data, int fd, short unsigned int events);
static int uart_midi_handler(void *data, int fd, unsigned short events);

#define MAX_BUF_SIZE      255
#define TIMER_INVERVAL_MS 200
#define MIDI_BAUD_RATE  31250

#define TEST_ACTIVE    0x0001
#define TEST_POWER_OK  0x0002
#define TEST_LINK_UP   0x0004
#define TEST_MIDI_OK   0x0008
#define TEST_6PIN_OK   0x0010
#define TEST_10PIN_OK  0x0020
#define TEST_ANCHO_OK  0x0040
#define TEST_AUDIO_OK  0x0080
#define TEST_SPDIF_OK  0x0100
#define TEST_PNOSCNPED 0x0200
#define TEST_PEDDRIVE  0x0400
#define TEST_ETHERNET  0x0800
#define TEST_SDCARD_OK 0x1000
#define TEST_USB_1_OK  0x2000
#define TEST_SWITCH_OK 0x4000
#define TEST_USB_2_OK  0x8000


#define FAIL 0
#define PASS 1
#define KEEP_TRYING 2
#define IGNORED 3

#define MAX_CHANNELS     16
#define MAX_DB_ERROR      3
#define CAPTURE_CHANNELS  2
#define RUN_NOTEST        0 
#define RUN_TETHERED     1 
#define RUN_STANDALONE    2
#define RUN_COMMANDLINE   3

enum{
  TEST_IDLE,
  TEST_ACTIVATE,
  TEST_POWER,
  TEST_LINK,
  TEST_MIDI,
  TEST_6PIN,
  TEST_10PIN,
  TEST_ANCHO,
  TEST_AUDIO,
  TEST_SPDIF,
  TEST_PNO_SCN_PED,
  TEST_PED_DRIVE,
  TEST_ETHERNET_PORT,
  TEST_SDCARD,
  TEST_USB_1,
  TEST_SWITCH,
  TEST_USB_2,
  FINISH_TEST,
  TEST_DONE,

  STST_IDLE,
  STST_ACTIVATE,
  STST_POWER,
  STST_LINK,
  STST_MIDI,
  STST_6PIN,
  STST_10PIN,
  STST_ANCHO,
  STST_AUDIO,
  STST_SPDIF,
  STST_PNO_SCN_PED,
  STST_PED_DRIVE,
  STST_ETHERNET_PORT,
  STST_SDCARD,
  STST_USB_1,
  STST_SWITCH,
  STST_USB_2,
  STST_FINISH,
  STST_TESTS_DONE,
  STST_REPORTS_DONE,
};
static const char* const test_state_name[] = {
  "IDLE",
  "ACTIVATE",
  "POWER",
  "LINK",
  "MIDI",
  "6PIN",
  "10PIN",
  "ANCHO",
  "AUDIO",
  "SPDIF",
  "PNO_SCN_PED",
  "PED_DRIVE",
  "ETHERNET_PORT",
  "SDCARD",
  "USB_1",
  "SWITCH",
  "USB_2",
  "FINISH_TEST",
  "DONE",
  "idle",
  "activate",
  "power",
  "link",
  "midi",
  "6pin",
  "10pin",
  "ancho",
  "audio",
  "spdif",
  "pno_scn_ped",
  "ped_drive",
  "ethernet_port",
  "sdcard",
  "usb_1",
  "switch",
  "usb_2",
  "finish_test",
  "tests_done",
  "reports_done"
};
//Single byte comm protocol from tester host DUT
enum{
  TESTER_TO_HOST_BOGUS_ZERO,
  TESTER_TO_HOST_START_TEST,
  TESTER_TO_HOST_POWER_GOOD,
  TESTER_TO_HOST_POWER_BAD,
  TESTER_TO_HOST_SERIAL_LOOP_ON, 
  TESTER_TO_HOST_SERIAL_LOOP_OFF, 
  TESTER_TO_HOST_PEDAL_LOOP_ON, 
  TESTER_TO_HOST_PEDAL_LOOP_OFF, 
  TESTER_TO_HOST_PEDAL_DRIVE_ON, 
  TESTER_TO_HOST_PEDAL_DRIVE_OFF, 
  TESTER_TO_HOST_RAIL_CURRENT_TEST_ON, 
  TESTER_TO_HOST_RAIL_CURRENT_TEST_OFF, 
  TESTER_TO_HOST_PED_CURRENT_TEST_ON, 
  TESTER_TO_HOST_PED_CURRENT_TEST_OFF, 
  TESTER_TO_HOST_DONE,
  TESTER_TO_HOST_PRINT_SUCCESS,
  TESTER_TO_HOST_PRINT_FAILURE,
  ASCII__TO_HOST_BOGUS_ZERO,
  ASCII__TO_HOST_START_TEST = 'A',
  ASCII__TO_HOST_POWER_GOOD,
  ASCII__TO_HOST_POWER_BAD,
  ASCII__TO_HOST_SERIAL_LOOP_ON, 
  ASCII__TO_HOST_SERIAL_LOOP_OFF, 
  ASCII__TO_HOST_PEDAL_LOOP_ON, 
  ASCII__TO_HOST_PEDAL_LOOP_OFF, 
  ASCII__TO_HOST_PEDAL_DRIVE_ON, 
  ASCII__TO_HOST_PEDAL_DRIVE_OFF, 
  ASCII__TO_HOST_RAIL_CURRENT_TEST_ON, 
  ASCII__TO_HOST_RAIL_CURRENT_TEST_OFF, 
  ASCII__TO_HOST_PED_CURRENT_TEST_ON, 
  ASCII__TO_HOST_PED_CURRENT_TEST_OFF, 
  ASCII__TO_HOST_DONE,
  ASCII__TO_HOST_PRINT_SUCCESS,
  ASCII__TO_HOST_PRINT_FAILURE
  }; 
static const char* const com_message_name[] = {
  "tester_to_host_start_test",
  "tester_to_host_power_good",
  "tester_to_host_power_bad",
  "tester_to_host_serial_loop_on", 
  "tester_to_host_serial_loop_off", 
  "tester_to_host_pedal_loop_on", 
  "tester_to_host_pedal_loop_off", 
  "tester_to_host_pedal_drive_on", 
  "tester_to_host_pedal_drive_off", 
  "tester_to_host_rail_current_test_on", 
  "tester_to_host_rail_current_test_off", 
  "tester_to_host_ped_current_test_on", 
  "tester_to_host_ped_current_test_off", 
  "tester_to_host_done",
  "tester_to_host_print_success",
  "tester_to_host_print_failure"
};


                           
/*--------------------------------------------------------------------------*\
 * Data types              
\*--------------------------------------------------------------------------*/
struct testhw_runtime
{
  unsigned char           *data;                  /**< poll data buffer */
  unsigned char           *midi_data;             /**< poll data buffer */
  struct midi9d_sharedmem  *sharedmem;            /**< pointer to system shared memory */
  int                     fd_uart;                /**< Test UART */
  int                     fd_midiconn_uart;       /**< MIDI UART */
  int                     fd_ppu_uart;            /**< PPU UART */
  int                     fd_buttons;
  FILE                   *fd_test_log;
  struct midi9_mainloop_t *loop;
  int button_bools;
  int tests_passed;
  int tests_failed;
  int test_state;
  int next_test;
  int test_first_call;
  int time_to_wait;
  int time_wait_started;
  int tester_on;            
  int power_good;           
  int tester_serial_loop_on;
  int tester_pedal_loop_on; 
  int tester_pedal_drive_on;
  int test_rail_current_on;
  int test_pedal_current_on;
  int run_mode;
  struct timeval thistime;
  struct timeval lasttime;
  struct timeval flashtime;
  struct timeval midi_out_time;
  int timediff;
  int flashdiff;
  int flash_error_on;
  int test_done;                                  //flag for printfs
  char midi_in_bytes[16];
  char ppu_data[16];
  int midi_in_count;
  int ped_lo_ma;
  int ped_hi_ma;
  int rail_lo_ma;
  int rail_hi_ma;
  float right_on_db;
  float left_on_db;
  float right_off_db;
  float left_off_db;
};

struct audio_stats
{
  float   rms;
  float  rmsc;
  int    mean;
  int16_t min;
  int16_t max;
};

#define MAX_LO_MA   30
#define MIN_HI_MA  950
#define MAX_HI_MA 1050
#define MIN_HI_MA_SO 1075
#define MAX_HI_MA_SO 1225

#define MAX_LO_DB_STANDALONE -50.0
#define MAX_LO_DB_TETHERED   -70.0
#define MAX_HI_DB_STANDALONE  -0.5
#define MAX_HI_DB_TETHERED    -0.5
#define MIN_HI_DB_STANDALONE  -4.5
#define MIN_HI_DB_TETHERED    -4.5

/*--------------------------------------------------------------------------*\
 * constants
\*--------------------------------------------------------------------------*/
static const char *const channel_name[MAX_CHANNELS] = {
  /*  0 */ "Front Left",
  /*  1 */ "Front Right",
  /*  2 */ "Rear Left",
  /*  3 */ "Rear Right",
  /*  4 */ "Center",
  /*  5 */ "LFE",
  /*  6 */ "Side Left",
  /*  7 */ "Side Right",
  /*  8 */ "Channel 9",
  /*  9 */ "Channel 10",
  /* 10 */ "Channel 11",
  /* 11 */ "Channel 12",
  /* 12 */ "Channel 13",
  /* 13 */ "Channel 14",
  /* 14 */ "Channel 15",
  /* 15 */ "Channel 16"
};

/*--------------------------------------------------------------------------*\
 * Global variables (are bad things)
\*--------------------------------------------------------------------------*/
static struct midi9_mainloop_t *g_loop;
static int timer_handler(void *data);

/*--------------------------------------------------------------------------*\
 * Helper functions
\*--------------------------------------------------------------------------*/
static void term(int signum)
{
  MIDI9_UNUSED_VARIABLE(signum);
  syslog(LOG_ERR, "testhw: Received SIGTERM, exiting...");
  midi9_mainloop_quit(g_loop);
}

static int input_params(int argc, char **argv)
{
  int c;
  static struct option long_options[] = {
    {"help",       no_argument,       NULL, 'h'},
    {"version",    no_argument,       NULL, 'v'},
    {"standalone", no_argument,       NULL, 's'},
    {"debug",      required_argument, NULL, 'd'},
    {0, 0, 0, 0}
  };
  
   while ((c = getopt_long(argc, argv, "hvsd:", long_options, NULL)) != -1)
   {
     switch (c)
     {
       case 'h':
         printf("usage: %s [OPTIONS]\n"
                      "\n"
                      "-h, --help        help\n"
                      "-v, --version     print version\n"
                      "-s, --standalone  run test without tester chassis\n"
                      "-d, --debug       debug level\n"
                      , argv[0]);
         exit(EXIT_SUCCESS);
         break;
       case 'v':
         fprintf(stderr, "%s", TESTHW_VERSION);
         exit(EXIT_SUCCESS);
         break;
       case 'd':
         printf("-d option found:%s\n",optarg);
         if (optarg) 
         {
           int level = atoi(optarg);
           
           printf("-d option found level:%d\n",level);
           
           switch (level)
           {
             case LOG_EMERG:
               printf("[hwtest]: Set syslog to = LOG_EMERG\n");
               break;
             case LOG_ALERT:
               printf("[hwtest]: Set syslog to = LOG_ALERT\n");
               break;
             case LOG_CRIT:
               printf("[hwtest]: Set syslog to = LOG_CRIT\n");
               break;
             case LOG_ERR:
               printf("[hwtest]: Set syslog to = LOG_ERR\n");
               break;
             case LOG_WARNING:
               printf("[hwtest]: Set syslog to = LOG_WARNING\n");
               break;
             case LOG_NOTICE:
               printf("[hwtest]: Set syslog to = LOG_NOTICE\n");
               break;
             case LOG_INFO:
               printf("[hwtest]: Set syslog to = LOG_INFO\n");
               break;
             case LOG_DEBUG:
               printf("[hwtest]: Set syslog to = LOG_DEBUG\n");
               break;
             default:  
               printf("[hwtest]: Bad syslog level %d, useing LOG_ERR\n", level);
               level = LOG_ERR;
               break;
           }    
           setlogmask(LOG_UPTO(level));
         }  
         break;
       case 's':
         printf("-s option found\n");
         return RUN_COMMANDLINE;
         break;
     }
   }
   /* Print any remaining command line arguments (not options). */
   if (optind < argc)
   {
     printf ("non-option ARGV-elements: ");
     while (optind < argc)
       printf ("%s ", argv[optind++]);
     putchar ('\n');
   }
   return 0;
}

void print_success_report(struct testhw_runtime *this)
{
  gettimeofday(&this->thistime, NULL);
  fprintf(this->fd_test_log,"mac id, serial number unknown \n");
  fprintf(this->fd_test_log,"pnoscan pedals, ancho port not tested \n");
  fprintf(this->fd_test_log,"PASSED ");
  fprintf(this->fd_test_log,"%s %s\n\n\n", __DATE__,__TIME__);
  //exit(EXIT_SUCCESS);//this caused the lights to quit on simple tester
  //midi9_mainloop_quit(g_loop);
}

void print_failure_report(struct testhw_runtime *this)//this to be appended to file
{
  gettimeofday(&this->thistime, NULL);
  fprintf(this->fd_test_log,"mac id, serial number unknown \n");
  fprintf(this->fd_test_log,"pnoscan pedals, ancho port not tested \n");
  fprintf(this->fd_test_log,"FAILED ");
  fprintf(this->fd_test_log,"%s %s\n\n\n", __DATE__,__TIME__);
  //exit(EXIT_SUCCESS);//this caused the lights to quit on simple tester
  //midi9_mainloop_quit(g_loop);
}
int send_message_to_tester(struct testhw_runtime *this, char *quip)
{
  //syslog(LOG_ERR,"%s",__FUNCTION__ );
  write(this->fd_uart, quip, strlen(quip));
  return 0;
}

int send_message_to_midi(struct testhw_runtime *this, char *quip)
{
  //syslog(LOG_ERR,"%s",__FUNCTION__ );
  write(this->fd_midiconn_uart, quip, strlen(quip));
  return 0;
}

void audiotest_calculate_rms(unsigned char *audiobuffer, int samples, int channels, int channel, int period, struct audio_stats *stat)
{
  int16_t *samp16 = (int16_t*) audiobuffer;
  long long square_sum = 0;
  long long corel_sum  = 0;
  long long mean_sum  = 0;
  int ii, chn;
  //int test_size    = samples - period;
  //int test_periods = samples / period;
  int test_size        =  ((samples / period) -1) * period;
  //printf(" %d = %d * (%d - 1)-- (%d/%d)\n", test_size, period, test_periods, samples, period);
  stat->rms    = 0;
  stat->rmsc   = 0;
  stat->mean   = 0;
  stat->min    = 0;
  stat->max    = 0;
  
  
  for (ii = 0; ii < test_size; ii++)
  {
    for (chn = 0; chn < channels; chn++) 
    {
      if (chn == channel) 
      {
        int16_t samp  = samp16[ii * channels+chn];
        int16_t sampc = samp16[(ii + period) * channels+chn];
        
        stat->min = MIN(stat->min, samp);
        stat->max = MAX(stat->max, samp);
        square_sum += (samp * samp);
        corel_sum  += (samp * sampc);
        mean_sum   += samp;
      }  
    }  
  }  
  stat->rms  = 20 * log10((sqrt(square_sum/test_size)/SHRT_MAX));
  stat->rmsc = 20 * log10((sqrt(corel_sum /test_size)/SHRT_MAX));
  stat->mean = mean_sum /test_size;
  //syslog(LOG_NOTICE, "mean:%6d min:%6d, max:%6d rms:% 6.2f dB correlation:% 6.2f dB", stat->mean, stat->min, stat->max, stat->rms,stat-> rmsc); 
}


static int audiotest_run_test(struct testhw_runtime *this) 
{
  struct midi9_alsa_audio_t *audio;
  struct audio_stats ostat;
  struct audio_stats rstat;
  struct audio_stats lstat;
  int audio_test_result = PASS;
  
  if (midi9_alsa_audio_create(&audio) == 0)
  {
    struct midi9_alsa_audio_device_t *playback, *capture;
    int   play_samples;
    int   play_channels;
    int   rec_samples;
    int   rec_channels;
    int   period;
    int   chn;
    float max_hi_db;
    float min_hi_db;
    float max_lo_db;
  
    if (midi9_ipc_fifo_msg_integer(MIDI9PLAYER_FIFO, MIDI9PLAYER_API_KILL_APP, 0) == 0)
      sleep(2);  /* wait for audio to die */
    if ((playback = audio->create(MIDI9_ALSA_AUDIO_PLAYBACK, SND_PCM_STREAM_PLAYBACK, SND_PCM_FORMAT_S16, 48000, 2)) == NULL)
    {
      syslog(LOG_ERR, "[%s]: Playback create failed", __FUNCTION__);
      return FAIL;
    }
  
    if ((capture = audio->create(MIDI9_ALSA_AUDIO_CAPTURE, SND_PCM_STREAM_CAPTURE, SND_PCM_FORMAT_S16, 48000, CAPTURE_CHANNELS)) == NULL)
    {                    
      syslog(LOG_ERR, "[%s]: Capture create failed", __FUNCTION__);
      return FAIL;
    }
    if(this->run_mode == RUN_TETHERED)
    {
      max_hi_db = MAX_HI_DB_TETHERED;
      min_hi_db = MIN_HI_DB_TETHERED;
      max_lo_db = MAX_LO_DB_TETHERED;
    }
    else
    {
      max_hi_db = MAX_HI_DB_STANDALONE;
      min_hi_db = MIN_HI_DB_STANDALONE;
      max_lo_db = MAX_LO_DB_STANDALONE;
    }
    
    play_samples  = playback->samples_per_buffer; 
    play_channels = playback->channels;
    rec_samples   = capture->samples_per_buffer;
    rec_channels  = capture->channels;
    period        = capture->rate / MIDI9_TEST_SINE_WAVE_FREQ;
 
    if (midi9_alsa_set_volume_percent(MIDI9_ALSA_AUDIO_DAC, 100) != 0)
    {
      syslog(LOG_WARNING, "ALSA volume set failed");
      return FAIL;
    }
    
    for (chn = 0; chn < playback->channels; chn++) 
    {
      int err = 0;
      int nn;
      int periods = (playback->rate * 3) / playback->samples_per_buffer;


      if (periods <= 0)
        periods = 1;
       
      fflush(stdout);

      for (nn = 0; nn < periods; nn++) 
      {
        int bytes;
      
        if (err)
          break;
        /* write data to selected channel, zero other channels */
        audio->test_signal(playback, chn, TEST_SINE);
        
        /* analyze selected channel */  
        audiotest_calculate_rms(playback->audiobuffer, play_samples, play_channels, chn, period, &ostat);
          
        /* write entire multichannel buffer to ALSA */  
        if ((bytes = audio->write(playback)) < 0)
        {
          syslog(LOG_WARNING, "[%s] FAIL: buffer write", __FUNCTION__);
          return FAIL;
        }  
     
        /* read 2-ch recorded data from ALSA */  
        if (audio->read(capture) < 0)
          syslog(LOG_WARNING, "[%s] FAIL: buffer read", __FUNCTION__);
        audiotest_calculate_rms(capture->audiobuffer, rec_samples, rec_channels, 0, period, &rstat);
        audiotest_calculate_rms(capture->audiobuffer, rec_samples, rec_channels, 1, period, &lstat);
        if (nn > 15) /* input buffers have zeros at start  and DC bleeding off caps */
        {
          if (chn == 0)
          {
            if( rstat.rms < max_hi_db &&  rstat.rms > min_hi_db && lstat.rms < max_lo_db && rstat.rmsc > min_hi_db)
              syslog(LOG_NOTICE, "PASS swapped mean:%6d min:%6d, max:%6d rms:% 6.2f dB corr:% 6.2f dB", rstat.mean, rstat.min, rstat.max, rstat.rms,rstat.rmsc); 
            else if( lstat.rms < max_hi_db &&  lstat.rms > min_hi_db && rstat.rms < max_lo_db && lstat.rmsc > min_hi_db)
              syslog(LOG_NOTICE, "PASS normal  mean:%6d min:%6d, max:%6d rms:% 6.2f dB corr:% 6.2f dB", lstat.mean, lstat.min, lstat.max, lstat.rms,lstat.rmsc); 
            else
            {
              fprintf(this->fd_test_log, "audio FAIL right out:% 6.2f dB right[%6.2f:%6.2f] dB left:[%6.2f dB:%6.2f] \n",ostat.rms,rstat.rms,rstat.rmsc,lstat.rms,lstat.rmsc); 
              fprintf(this->fd_test_log, "audio FAIL limits MAX_HI:%f MIN_HI:%f MAX_LO:%f\n",  max_hi_db, min_hi_db, max_lo_db);
              fprintf(this->fd_test_log, "audio FAIL out   mean:%4d min:%6d max:%6d \n",ostat.mean, ostat.min, ostat.max); 
              fprintf(this->fd_test_log, "audio FAIL left  mean:%4d min:%6d max:%6d \n",lstat.mean, lstat.min, lstat.max); 
              fprintf(this->fd_test_log, "audio FAIL right mean:%4d min:%6d max:%6d \n",rstat.mean, rstat.min, rstat.max); 
              err++;
            }
          }    
          if (chn == 1)
          {
            if( rstat.rms < max_hi_db &&  rstat.rms > min_hi_db && lstat.rms < max_lo_db && rstat.rmsc > min_hi_db)
              syslog(LOG_NOTICE, "PASS normal  mean:%6d min:%6d, max:%6d rms:% 6.2f dB corr:% 6.2f dB", rstat.mean, rstat.min, rstat.max, rstat.rms,rstat.rmsc); 
            else if( lstat.rms < max_hi_db &&  lstat.rms > min_hi_db && rstat.rms < max_lo_db && lstat.rmsc > min_hi_db)
              syslog(LOG_NOTICE, "PASS swapped mean:%6d min:%6d, max:%6d rms:% 6.2f dB corr:% 6.2f dB", lstat.mean, lstat.min, lstat.max, lstat.rms,lstat.rmsc); 
            else
            {
              fprintf(this->fd_test_log, "audio FAIL left  out:% 6.2f dB right[%6.2f:%6.2f] dB left:[%6.2f dB:%6.2f] \n",ostat.rms,rstat.rms,rstat.rmsc,lstat.rms,lstat.rmsc); 
              fprintf(this->fd_test_log, "audio FAIL limits MAX_HI:%f MIN_HI:%f MAX_LO:%f\n",  max_hi_db, min_hi_db, max_lo_db);
              fprintf(this->fd_test_log, "audio FAIL out   mean:%4d min:%6d max:%6d\n ",ostat.mean, ostat.min, ostat.max); 
              fprintf(this->fd_test_log, "audio FAIL left  mean:%4d min:%6d max:%6d\n ",lstat.mean, lstat.min, lstat.max); 
              fprintf(this->fd_test_log, "audio FAIL right mean:%4d min:%6d max:%6d\n ",rstat.mean, rstat.min, rstat.max); 
              err++;
            }
          }    
        }
      }
      
      if (playback->bytes_per_buffer > (nn * playback->samples_per_buffer)) 
      {
        snd_pcm_drain(playback->handle);
        snd_pcm_prepare(playback->handle);
      }
      if (err > 0)
        audio_test_result = FAIL;
    }
    audio->destroy(capture);
    audio->destroy(playback);
    midi9_alsa_audio_destroy(audio);
  }  
  else
    audio_test_result = FAIL;
  return audio_test_result;
}

/*--------------------------------------------------------------------------*\
 * handler functions
\*--------------------------------------------------------------------------*/

static void check_test(struct testhw_runtime *this,int test_passed, int display_boolean, int next__test)
{
  
  switch(test_passed)
  {
    case FAIL:
      //syslog(LOG_ERR,"%s:failed",test_state_name[this->next_test]);
      //this->tests_passed |= display_boolean;
      this->tests_failed  |= display_boolean;//???? why was this missing
      this->next_test     = next__test;
      this->time_to_wait  = 500;
      this->lasttime      =  this->thistime;
      this->test_done = 1;
      break;
    case PASS:
      //syslog(LOG_ERR,"%s:passed",test_state_name[this->next_test]);
      this->tests_passed |= display_boolean;
      this->next_test    = next__test;
      this->time_to_wait  = 500;
      this->lasttime      =  this->thistime;
      this->test_done = 1;
      break;
    case KEEP_TRYING:
      if (this->time_to_wait < this->timediff)
      {
        //syslog(LOG_ERR,"%s:failed trying",test_state_name[this->next_test]);
        this->tests_failed  |= display_boolean;
        this->next_test     = next__test;
        this->time_to_wait  = 500;
        this->lasttime      =  this->thistime;
        this->test_done = 1;
      }
      break;
    case IGNORED:
      //syslog(LOG_ERR,"%s:ignored",test_state_name[this->next_test]);
      this->next_test     = next__test;
      this->time_to_wait  = 500;
      this->lasttime      =  this->thistime;
      this->test_done = 1;
      break;
  }
}
static void check_rail_millamps(struct testhw_runtime *this)
{
  struct midi9d_sharedmem *sharedmem = this->sharedmem;
  struct midi9_runtime *run = &sharedmem->runtime;
 
  this->rail_hi_ma = run->powersupply.solenoid.slow.milliamps;
  this->ped_lo_ma  = run->powersupply.pedal.slow.milliamps;
}
static void check_ped_millamps(struct testhw_runtime *this)
{
  struct midi9d_sharedmem *sharedmem = this->sharedmem;
  struct midi9_runtime *run = &sharedmem->runtime;
 
  this->rail_lo_ma = run->powersupply.solenoid.slow.milliamps;
  this->ped_hi_ma  = run->powersupply.pedal.slow.milliamps;
}
static void check_milliamps(struct testhw_runtime *this)
{
  struct midi9d_sharedmem *sharedmem = this->sharedmem;
  struct midi9_runtime *run = &sharedmem->runtime;
 
  switch(this->test_state)
  {
    case STST_AUDIO:
      this->rail_lo_ma = run->powersupply.solenoid.slow.milliamps;
      this->ped_lo_ma  = run->powersupply.pedal.slow.milliamps;
      break;
    case STST_PNO_SCN_PED:
      this->rail_hi_ma = run->powersupply.solenoid.slow.milliamps;
      this->ped_hi_ma  = run->powersupply.pedal.slow.milliamps;
      break;
   
  }
}

static void set_ped_width(unsigned char width)
{
  //char set_sust_ped_width = {SYS_EXCL,OUR_ID,PM2_CMDS ,SET_PED_WIDTH(0x70) ,pulse_width, EOX};
  //unsigned char ppu_set_ped_width[7] =   { 0xf0, 0x09, 0x01, 0x70, 0x00, 0xf7};
  unsigned char ppu_set_ped_width[6];
  
  ppu_set_ped_width[0] = 0xf0; 
  ppu_set_ped_width[1] = 0x09; 
  ppu_set_ped_width[2] = 0x01; 
  ppu_set_ped_width[3] = 0x70; 
  ppu_set_ped_width[4] = width & 0x7f;
  ppu_set_ped_width[5] = 0xf7;
  
  midi9_ipc_fifo_write_data(PPU_FIFO, ppu_set_ped_width, sizeof(ppu_set_ped_width));
}
/*
  messages that are tested but unused with tester.
  
  send_message_to_tester(this, "ped_test_on.");
  send_message_to_tester(this, "ped_down_on.");
  send_message_to_tester(this, "ped_down_off.");
  send_message_to_tester(this, "ped_test_off.");
*/
void a_little_light_show(struct midi9_driver *driver, int sleep_time, int leds)
{
  sleep(sleep_time);
  driver->keysolenoid.pwm_operating_mode = 0x10 | (leds << 8); 
  midi9_drivercomm_write(MIDI9_DRIVER_KEY_PARAMS, &driver->keysolenoid);
  //syslog(LOG_ERR,"%s - countdown",__FUNCTION__ );
}


static int timer_handler(void *data)//this is set to TIMER_INVERVAL_MS
{
  struct testhw_runtime *this = (struct testhw_runtime *)data;
  struct midi9d_sharedmem *sharedmem = this->sharedmem;
  struct midi9_runtime *run = &sharedmem->runtime;
  struct midi9_driver *driver = &sharedmem->driver;
  int test_results = 0;
  //unsigned char ppu_set_ped_width[7] =   { 0xf0, 0x09, 0x01, 0x70, 0x00, 0xf7};
  //char set_sust_ped_width = {SYS_EXCL,OUR_ID,PM2_CMDS ,SET_PED_WIDTH(0x70) ,pulse_width, EOX};
  
  if (!this)
    return 1;
  
  gettimeofday(&this->thistime, NULL);
  this->timediff = USEC_TO_MSEC(midi9time_timeval_diff_us(this->lasttime));
  this->test_done = 0;
  //syslog(LOG_ERR,"%s %s state#:%d",__FUNCTION__, test_state_name[this->test_state],this->test_state);
  switch(this->test_state)
  {
    case TEST_IDLE:
        this->test_state    = TEST_ACTIVATE;
        //send_message_to_tester(this, ".Start.");//this was handled before loop started
        send_message_to_tester(this, "ped_ma_off.");
        send_message_to_tester(this, "rail_ma_off.");
      break;
    case TEST_ACTIVATE:
      send_message_to_midi(this,"atest12");
      this->midi_out_time = this->thistime;
      test_results = PASS;
      a_little_light_show(driver, 1, 0xffff);
      a_little_light_show(driver, 1, 0x3fff);
      a_little_light_show(driver, 1, 0x0fff);
      a_little_light_show(driver, 1, 0x03ff);
      a_little_light_show(driver, 1, 0x00ff);
      a_little_light_show(driver, 1, 0x003f);
      a_little_light_show(driver, 1, 0x000f);
      a_little_light_show(driver, 1, 0x0007);
      a_little_light_show(driver, 1, 0x0003);
      a_little_light_show(driver, 1, 0x0001);
      a_little_light_show(driver, 1, 0x0000);
      gettimeofday(&this->lasttime, NULL);
      check_test(this, test_results , TEST_ACTIVE, TEST_POWER);
      break;
    case TEST_POWER:
      syslog(LOG_NOTICE,"TEST_POWER  power is %s",this->power_good?"on":"off" );
      if(this->power_good)
          test_results = PASS;
      else
          test_results = FAIL;
      check_test(this, test_results , TEST_POWER_OK , TEST_LINK);
      break;
    case TEST_LINK:
      //send tester reqest for uart loop back
      //verify loop back request recieved
      //test_results = loop_back_recieved();
      //send a midi note on
      test_results = PASS;
      check_test(this, test_results , TEST_LINK_UP  , TEST_ANCHO );
      break;
    case TEST_ANCHO://aint not ancho test
      test_results = PASS;
      check_test(this, test_results , TEST_ANCHO_OK , TEST_MIDI);
      break;
    case TEST_MIDI:
      //syslog(LOG_ERR,"%s Midi test delay:%ldms",__FUNCTION__, TIMEVAL_DIFF_MSEC(&this->midi_out_time, &this->thistime));
      if(strcmp(this->midi_in_bytes,"atest12") == 0)
        test_results = PASS;
      else
      {
        test_results = FAIL;
        fprintf(this->fd_test_log,"%s MIDI TEST failure recieved:%s\n",__FUNCTION__, this->midi_in_bytes );
      }
      check_test(this, test_results , TEST_MIDI_OK  , TEST_AUDIO );
      break;
    case TEST_AUDIO:
      //this audio test just tests 2 channels one of which is dead.
      //hopefully someday we can get a clean audio system.. 
      //I cant tell you how frustrating this schlock is. 11-6-2013 dts
      //syslog(LOG_NOTICE,"%s AUDIO TEST since midiout:%ldms",__FUNCTION__, TIMEVAL_DIFF_MSEC(&this->midi_out_time, &this->thistime));
      
      test_results = audiotest_run_test(this);
      //syslog(LOG_ERR,"%s AUDIO TEST %s",__FUNCTION__, test_results == PASS?"pass":"failure" );
      check_test(this, test_results , TEST_AUDIO_OK , TEST_SPDIF);
      set_ped_width(0x3B);//set up for ADC and PED solenoid FET drive
      gettimeofday(&this->lasttime, NULL);
      send_message_to_tester(this, "ped_ma_on.");//green
      break;
    case TEST_SPDIF: //not a teset today.. Maybe someday..
      //send square out chan 1R - verify ((Vinr == .175 * Vor) && (Vinl == 0))
      if (this->timediff > 500)
      {
        check_rail_millamps(this);
        send_message_to_tester(this, "ped_ma_off.");
        send_message_to_tester(this, "rail_ma_on.");
        test_results = PASS;
        check_test(this, test_results , TEST_SPDIF_OK , TEST_PNO_SCN_PED);
      }
      break;
    case TEST_PNO_SCN_PED:
      //shut down serial loop_back
      //set pedal trigger positions as needed by tester
      //set ped_test_on high
      //set ped_test_down high All three pedals should report
      //set ped_test_down low All three pedals should report
      //set test_results variable
      //clear ped test stuff..
      syslog(LOG_NOTICE,"%s PNOSCAN PED TEST since midiout:%ldms",__FUNCTION__, USEC_TO_MSEC(midi9time_timeval_subtract_us(this->thistime, this->midi_out_time)));
      if (this->timediff > 500)
      {
        check_ped_millamps(this);
        //send_message_to_tester(this, "ped_ma_off.");
        send_message_to_tester(this, "rail_ma_off.");
        set_ped_width(0x00);
        test_results = PASS;//just to light the light .. no pianoscan ped tested to date
        check_test(this, test_results , TEST_PNOSCNPED, TEST_PED_DRIVE);
      }
      break;
    case TEST_PED_DRIVE:
      //set pedal width to ?%  
      //set pwm_rail_i verify 5amps of rail current (ped current 0)
      //set pwm_ped_i verify 5amps of ped current   rail current still
      //set pedal width to 1/2%  
      //set pwm_rail_i verify 2.5amps of rail current (ped current 0)
      //set pwm_ped_i verify 2.5amps of ped current   rail current still
      //ped to zero and test booleans off
      //set test_results variable
      if(this->rail_hi_ma > MIN_HI_MA && this->rail_hi_ma < MAX_HI_MA && this->rail_lo_ma < MAX_LO_MA &&
         this->ped_hi_ma  > MIN_HI_MA && this->ped_hi_ma  < MAX_HI_MA && this->ped_lo_ma  < MAX_LO_MA)
        test_results = PASS;
      else
      {
        test_results = FAIL;
        fprintf(this->fd_test_log,"TEST_PED_DRIVE FAIL rail:[%d:%d] ped:[%d:%d]\n",this->rail_hi_ma,this->rail_lo_ma,this->ped_hi_ma,this->ped_lo_ma);
        fprintf(this->fd_test_log,"TEST_PED_DRIVE FAIL limits MAX_HI_MA: %d MIN_HI_MA: %d MAX_LO_MA: %d\n",  MAX_HI_MA, MIN_HI_MA, MAX_LO_MA);
      }
      
      check_test(this, test_results , TEST_PEDDRIVE , TEST_6PIN);
      break;
    case TEST_6PIN:
      //loop back should have already produce NumNotes = 1;
      if(run->pnoscan.pscan_6r.NumNotes == 1)
        test_results = PASS;
      else
        test_results = FAIL;
      check_test(this, test_results , TEST_6PIN_OK  , TEST_10PIN);
      break;
    case TEST_10PIN:
      if(run->pnoscan.pscan_10r.NumNotes == 1)
        test_results = PASS;
      else
        test_results = FAIL;
      check_test(this, test_results , TEST_10PIN_OK  , TEST_ETHERNET_PORT);
      break;
    case TEST_ETHERNET_PORT:
      //check for IP address of dongle?
      test_results = PASS;
      check_test(this, test_results , TEST_ETHERNET , TEST_SDCARD);
      break;
    case TEST_SDCARD:
      //check for trick file
      if(midi9_util_is_media_mounted(MEDIA_DIR_SDCARD) == 0)
      {
        test_results = FAIL;
        fprintf(this->fd_test_log, "FAIL no sdcard found\n");
      }
      else
        test_results = PASS;
      check_test(this, test_results , TEST_SDCARD_OK, TEST_USB_1);
      break;
    case TEST_USB_1:
      if(midi9_util_is_media_mounted(MEDIA_DIR_USBDRIVE) == 0)
      {
        test_results = FAIL;
        fprintf(this->fd_test_log, "FAIL no usb drive found\n");
      }
      else
        test_results = PASS;
      check_test(this, test_results , TEST_USB_1_OK , TEST_SWITCH);
      break;
    case TEST_SWITCH:
      //verify all three switches were pressed independantly
      if(this->button_bools == 0x77)
        test_results = PASS;
      else
      {
        test_results = FAIL;
        fprintf(this->fd_test_log, "FAIL switch button bools:%x\n",this->button_bools);
      }
      check_test(this, test_results , TEST_SWITCH_OK, TEST_USB_2);
      break;
    case TEST_USB_2:
      //check for trick file
      set_ped_width(0x0);
      test_results = PASS;
      check_test(this, test_results , TEST_USB_2_OK , FINISH_TEST);
      break;
    case FINISH_TEST:
        if(this->tests_failed)
          send_message_to_tester(this, "Fail.");
        else  
          send_message_to_tester(this, "Done.");
        this->test_state   = TEST_DONE;
      break;
    case TEST_DONE:
        this->test_state   = TEST_DONE;
      break;                                      
    case STST_IDLE:
        this->test_state    = STST_ACTIVATE;
      break;
    case STST_ACTIVATE:
      send_message_to_midi(this,"atest12");
      this->midi_out_time = this->thistime;
      test_results = PASS;
      a_little_light_show(driver, 1, 0x0000);
      a_little_light_show(driver, 1, 0x0001);
      a_little_light_show(driver, 1, 0x0003);
      a_little_light_show(driver, 1, 0x0007);
      a_little_light_show(driver, 1, 0x000f);
      a_little_light_show(driver, 1, 0x003f);
      a_little_light_show(driver, 1, 0x00ff);
      a_little_light_show(driver, 1, 0x03ff);
      a_little_light_show(driver, 1, 0x0fff);
      a_little_light_show(driver, 1, 0x3fff);
      a_little_light_show(driver, 1, 0xffff);
      gettimeofday(&this->lasttime, NULL);
      check_test(this, test_results , TEST_ACTIVE, STST_POWER);
      break;
    case STST_POWER://no power test here
      test_results = PASS;
      check_test(this, test_results , TEST_POWER_OK , STST_LINK);
      break;
    case STST_LINK://no link here
      test_results = PASS;
      check_test(this, test_results , TEST_LINK_UP  , STST_ANCHO );
      break;
    case STST_ANCHO://aint not ancho test
      test_results = PASS;
      check_test(this, test_results , TEST_ANCHO_OK , STST_MIDI);
      break;
    case STST_MIDI:
      //syslog(LOG_ERR,"%s Midi test delay:%ldms",__FUNCTION__, TIMEVAL_DIFF_MSEC(&this->midi_out_time, &this->thistime));
      if(strcmp(this->midi_in_bytes,"atest12") == 0)
        test_results = PASS;
      else
      {
        test_results = FAIL;
        fprintf(this->fd_test_log,"%s MIDI TEST failure recieved:%s\n",__FUNCTION__, this->midi_in_bytes );
      }
      check_test(this, test_results , TEST_MIDI_OK  , STST_AUDIO );
      break;
    case STST_AUDIO:
      //this audio test just tests 2 channels one of which is dead.
      //hopefully someday we can get a clean audio system.. 
      //I cant tell you how frustrating this schlock is. 11-6-2013 dts
      //syslog(LOG_NOTICE,"%s AUDIO TEST since midiout:%ldms",__FUNCTION__, TIMEVAL_DIFF_MSEC(&this->midi_out_time, &this->thistime));
      
      test_results = audiotest_run_test(this);
      //syslog(LOG_ERR,"%s AUDIO TEST %s",__FUNCTION__, test_results == PASS?"pass":"failure" );
      check_test(this, test_results , TEST_AUDIO_OK , STST_SPDIF);
      check_milliamps(this);
      set_ped_width(0x3B);//set up for ADC and PED solenoid FET drive
      gettimeofday(&this->lasttime, NULL);
      break;
    case STST_SPDIF://spdif not really tested
      test_results = PASS;
      check_test(this, test_results , TEST_SPDIF_OK , STST_PNO_SCN_PED);
      break;
    case STST_PNO_SCN_PED:
      syslog(LOG_NOTICE,"%s Standalone PNOSCAN PED TEST since midiout:%ldms",__FUNCTION__, USEC_TO_MSEC(midi9time_timeval_subtract_us(this->thistime, this->midi_out_time)));
      if (this->timediff > 500)
      {
        check_milliamps(this);
        set_ped_width(0x00);
        test_results = PASS;//just to light the light .. no pianoscan ped tested to date
        check_test(this, test_results , TEST_PNOSCNPED, STST_PED_DRIVE);
      }
      break;
    case STST_PED_DRIVE:
      if(this->rail_hi_ma > MIN_HI_MA_SO && this->rail_hi_ma < MAX_HI_MA_SO && this->rail_lo_ma < MAX_LO_MA &&
         this->ped_hi_ma  > MIN_HI_MA_SO && this->ped_hi_ma  < MAX_HI_MA_SO && this->ped_lo_ma  < MAX_LO_MA)
        test_results = PASS;
      else
      {
        test_results = FAIL;
        fprintf(this->fd_test_log,"STST_PED_DRIVE FAIL rail:[%d:%d] ped:[%d:%d]\n",this->rail_hi_ma,this->rail_lo_ma,this->ped_hi_ma,this->ped_lo_ma);
        fprintf(this->fd_test_log,"STST_PED_DRIVE FAIL limits MAX_HI_MA_SO: %d MIN_HI_MA_SO: %d MAX_LO_MA: %d\n",  MAX_HI_MA_SO, MIN_HI_MA_SO, MAX_LO_MA);
      }
      
      check_test(this, test_results , TEST_PEDDRIVE , STST_6PIN);
      break;
    case STST_6PIN: //loop back should have already produce NumNotes = 1;
      if(run->pnoscan.pscan_6r.NumNotes == 1)
        test_results = PASS;
      else
        test_results = FAIL;
      check_test(this, test_results , TEST_6PIN_OK  , STST_10PIN);
      break;
    case STST_10PIN:
      if(run->pnoscan.pscan_10r.NumNotes == 1)
        test_results = PASS;
      else
        test_results = FAIL;
      check_test(this, test_results , TEST_10PIN_OK  , STST_ETHERNET_PORT);
      break;
    case STST_ETHERNET_PORT://not test here
      //check for IP address of dongle?
      test_results = PASS;
      check_test(this, test_results , TEST_ETHERNET , STST_SDCARD);
      break;
    case STST_SDCARD: //check for any file
      if(midi9_util_is_media_mounted(MEDIA_DIR_SDCARD) == 0)
      {
        test_results = FAIL;
        fprintf(this->fd_test_log, "FAIL no sdcard found\n");
      }
      else
        test_results = PASS;
      check_test(this, test_results , TEST_SDCARD_OK, STST_USB_1);
      break;
    case STST_USB_1:
      if(midi9_util_is_media_mounted(MEDIA_DIR_USBDRIVE) == 0)
      {
        test_results = FAIL;
        fprintf(this->fd_test_log, "FAIL no usb drive found\n");
      }
      else
        test_results = PASS;
      check_test(this, test_results , TEST_USB_1_OK , STST_SWITCH);
      break;
    case STST_SWITCH://verify all three switches were pressed independantly
      if(this->button_bools == 0x77)
        test_results = PASS;
      else if(this->button_bools)
        test_results = FAIL;
      else
        test_results = IGNORED;
      check_test(this, test_results , TEST_SWITCH_OK, STST_USB_2);
      this->button_bools  = 0;
      break;
    case STST_USB_2:      //check for trick file
      set_ped_width(0x0);
      test_results = IGNORED;
      check_test(this, test_results , TEST_USB_2_OK , STST_FINISH);
      break;
    case STST_FINISH:
        //syslog(LOG_ERR,"%s:",test_state_name[this->test_state]);
        this->test_done   = 0;
        this->test_state = STST_TESTS_DONE;
      break;
    case STST_TESTS_DONE:
      if(this->button_bools == 0x77)
      {
      
        syslog(LOG_ERR,"tests complete printed now %s %s",__DATE__,__TIME__);
        this->tests_failed &= (0xffff ^ TEST_SWITCH_OK);
        this->tests_passed |=  TEST_SWITCH_OK;
        this->tests_passed |=  TEST_USB_2_OK;
        
        if(this->tests_failed)
          print_failure_report(this);
        else  
          print_success_report(this);
        this->test_state = STST_REPORTS_DONE;
        fclose(this->fd_test_log);
      }
      else if(this->button_bools)
        check_test(this, FAIL , TEST_SWITCH_OK, STST_TESTS_DONE);
      else
      {
        //syslog(LOG_ERR,"%s:this->button_bools:%02x ",test_state_name[this->test_state],this->button_bools);
        this->test_state = STST_TESTS_DONE;
      }
      this->test_done   = 0;//poorly named but 
      break;                                      
    case STST_REPORTS_DONE:
      this->test_state = STST_REPORTS_DONE;
      this->test_done   = 0;//poorly named but 
      break;                                      
  }  
  //this->flashdiff = TIMEVAL_DIFF_MSEC(&this->flashtime,  &this->thistime);
  //if(this->flashdiff > 199)
  {
     //syslog(LOG_ERR,"%s %s flasher",__FUNCTION__, test_state_name[this->test_state]);
    
     if(this->flash_error_on)
     {
       this->flash_error_on = 0;
       driver->keysolenoid.pwm_operating_mode = 0x10 | (this->tests_passed << 8) | (this->tests_failed << 8);
     }
     else
     {
       this->flash_error_on = 1;
       driver->keysolenoid.pwm_operating_mode = 0x10 | (this->tests_passed << 8);
     }
     midi9_drivercomm_write(MIDI9_DRIVER_KEY_PARAMS, &driver->keysolenoid);
  }
  
  if(this->test_done)
  {
    if(test_results == KEEP_TRYING)
       test_results = FAIL;
    fprintf(this->fd_test_log,"%13s %s\n", test_state_name[this->test_state],test_results?"PASSED":"FAILED");
    this->test_state = this->next_test;
  }
  return 1;
}


/* Handle data from UART */
static int uart_handler(void *data, int fd, unsigned short events)
{
  struct testhw_runtime *this = (struct testhw_runtime *)data;
  //struct midi9d_sharedmem *sharedmem = this->sharedmem;
  //struct midi9_driver *driver = &sharedmem->driver;
  
  if (events & POLLIN)
  {
    int cnt;

    if ((cnt = read(fd, this->data, (MAX_BUF_SIZE-1))) > 0)
    {
      int ii;
      
      for (ii = 0; ii < cnt; ii++)
      {
        
        //syslog(LOG_NOTICE,"Received from test UART: %d",this->data[ii]);
        syslog(LOG_NOTICE,"Received from test UART: %s",com_message_name[this->data[ii]]);
        switch(this->data[ii])
        {
          case ASCII__TO_HOST_START_TEST:
          case TESTER_TO_HOST_START_TEST:
            this->tester_on = 1;
            break;
          case ASCII__TO_HOST_POWER_GOOD:
          case TESTER_TO_HOST_POWER_GOOD:
            this->power_good = PASS;
            break;
          case ASCII__TO_HOST_POWER_BAD:
          case TESTER_TO_HOST_POWER_BAD:
            this->power_good = FAIL;
            break;
          case ASCII__TO_HOST_SERIAL_LOOP_ON :
          case TESTER_TO_HOST_SERIAL_LOOP_ON :
            this->tester_serial_loop_on = 1;
            break;
          case ASCII__TO_HOST_SERIAL_LOOP_OFF :
          case TESTER_TO_HOST_SERIAL_LOOP_OFF :
            this->tester_serial_loop_on = 0;
            break;
          case ASCII__TO_HOST_PEDAL_LOOP_ON :
          case TESTER_TO_HOST_PEDAL_LOOP_ON :
            this->tester_pedal_loop_on = 1;
            break;
          case ASCII__TO_HOST_PEDAL_LOOP_OFF :
          case TESTER_TO_HOST_PEDAL_LOOP_OFF :
            this->tester_pedal_loop_on = 0;
            break;
          case ASCII__TO_HOST_PEDAL_DRIVE_ON :
          case TESTER_TO_HOST_PEDAL_DRIVE_ON :
            this->tester_pedal_drive_on = 1;
            break;
          case ASCII__TO_HOST_PEDAL_DRIVE_OFF :
          case TESTER_TO_HOST_PEDAL_DRIVE_OFF :
            this->tester_pedal_drive_on = 0;
            break;
          case ASCII__TO_HOST_RAIL_CURRENT_TEST_ON :
          case TESTER_TO_HOST_RAIL_CURRENT_TEST_ON :
            this->test_rail_current_on = 1;
            break;
          case ASCII__TO_HOST_RAIL_CURRENT_TEST_OFF :
          case TESTER_TO_HOST_RAIL_CURRENT_TEST_OFF :
            this->test_rail_current_on = 0;
            break;
          case ASCII__TO_HOST_PED_CURRENT_TEST_ON :
          case TESTER_TO_HOST_PED_CURRENT_TEST_ON :
            this->test_pedal_current_on = 1;
            break;
          case ASCII__TO_HOST_PED_CURRENT_TEST_OFF :
          case TESTER_TO_HOST_PED_CURRENT_TEST_OFF :
            this->test_pedal_current_on = 0;
            break;
          case ASCII__TO_HOST_DONE:
          case TESTER_TO_HOST_DONE:
            this->tester_on = 0;
            break;
          case ASCII__TO_HOST_PRINT_SUCCESS:
          case TESTER_TO_HOST_PRINT_SUCCESS:
            print_success_report(this);
            exit(EXIT_SUCCESS);//bail out if from host (big tester)
            break;
          case ASCII__TO_HOST_PRINT_FAILURE:
          case TESTER_TO_HOST_PRINT_FAILURE:
            print_failure_report(this);
            exit(EXIT_SUCCESS);//bail out if from host (big tester)
            break;
        }      
      }
    }
    if (cnt == -1)
      syslog(LOG_ERR, "[%s]: read error: %s", __FUNCTION__, strerror(errno));
  } 
  return 0;
}

/* Handle data from MIDI UART */
/* Handle data from MIDI UART */
static int uart_midi_handler(void *data, int fd, unsigned short events)
{
  struct testhw_runtime *this = (struct testhw_runtime *)data;
  
  if (events & POLLIN)
  {
    int cnt;

    if ((cnt = read(fd, this->midi_data, (MAX_BUF_SIZE-1))) > 0)
    {
      {
        int ii;
        
        for (ii = 0; ii < cnt; ii++)
        {
          if (this->midi_data[ii] == 'a')
             this->midi_in_count = 0;
          this->midi_in_bytes[this->midi_in_count++] = this->midi_data[ii];
        } 
        this->midi_in_bytes[this->midi_in_count] = 0;
        if(1)
        {
          syslog(LOG_NOTICE,"Received %d bytes from MIDI UART: %s",this->midi_in_count,this->midi_in_bytes); 
          syslog(LOG_NOTICE,"%s Midi test delay:%ldms",__FUNCTION__, USEC_TO_MSEC(midi9time_timeval_subtract_us(this->thistime, this->midi_out_time)));
        }
      }
    }
    if (cnt == -1)
      syslog(LOG_ERR, "[%s]: read error: %s", __FUNCTION__, strerror(errno));
  } 
  return 0;
}

static void parse_button_event(struct input_event *ev,struct testhw_runtime *this)
{
  if (!ev)
    return;

  if (ev->type == EV_KEY)
  {
    switch (ev->value)
    {
      case BUTTON_ON:
        switch (ev->code)
        {
          case BUTTON_LEFT:
            this->button_bools |= 0x01; 
            /* Left button ON */
            break;
          case BUTTON_CENTER:
            this->button_bools |= 0x02; 
            /* Center button ON */
            break;
          case BUTTON_RIGHT:
            this->button_bools |= 0x04; 
            /* Right button ON */
            break;
        }
        break;
      case BUTTON_OFF:
        switch (ev->code)
        {
          case BUTTON_LEFT:         /* Left button */
            this->button_bools |= 0x10; 
            break;
          case BUTTON_CENTER:         /* Center button */
            this->button_bools |= 0x20; 
            break;
          case BUTTON_RIGHT:
            this->button_bools |= 0x40; 
            break;
        }
        break;
      default:
        syslog(LOG_WARNING, "[%s]: Unknown value = %d\n", __FUNCTION__, ev->value);
        break;
    }
    //syslog(LOG_ERR, "[%s]button bools:%02x\n", __FUNCTION__, this->button_bools);
  }
}


static int button_device_handler(void *data, int fd, short unsigned int events)
{
  struct testhw_runtime *this = (struct testhw_runtime *)data;
  struct input_event ev[64];
  size_t rb;
  int ii;

  MIDI9_UNUSED_VARIABLE(events);
  rb = read(fd, ev, sizeof(struct input_event)*64);
  if (rb < (int) sizeof(struct input_event)) 
    syslog(LOG_WARNING, "[%s]: short read\n", __FUNCTION__);
  for (ii = 0; ii < (int) (rb / sizeof(struct input_event)); ii++)
    parse_button_event(&ev[ii], this);
  return 0;
}


int test_uart_open(struct testhw_runtime *this, const char *device, int baudrate)
{
  //int fd = -1;
  int cnt;
  int ii;
  
  this->fd_uart = -1;
  if ((this->fd_uart = open(device, O_RDWR | O_NOCTTY | O_NONBLOCK)) >= 0) 
  {
    struct termios newtio;
    int err;

    tcflush(this->fd_uart, TCIOFLUSH);
    memset(&newtio, 0, sizeof(newtio));
    cfmakeraw(&newtio);            /* set up in raw mode */
    newtio.c_cflag |= CLOCAL;      /* ignore modem control lines */
    newtio.c_cflag &= ~CRTSCTS;    /* turn off RTS/CTS flow control */
    newtio.c_cc[VMIN]  = 1;        /* minimum number of charactersto read */
    newtio.c_cc[VTIME] = 0;        /* no timer expiration on blocking read */
    err = cfsetspeed(&newtio, baudrate);
    if (err < 0)
      syslog(LOG_WARNING, "[%s]: baud rate %d hard coded. %d", __FUNCTION__, baudrate, err);
    tcsetattr(this->fd_uart, TCSANOW, &newtio);
  }
  //return fd;
  else
    return 0;
  send_message_to_tester(this, ".Start.");
  sleep(1);
  if ((cnt = read(this->fd_uart, this->data, (MAX_BUF_SIZE-1))) > 0)
  {
    for (ii = 0; ii < cnt; ii++)
    {
      if((this->data[ii] == 1) || (this->data[ii] == 'A'))
      {
        close(this->fd_uart);
        //syslog(LOG_ERR,"Magic 1 to start test");
        this->run_mode = RUN_TETHERED;
        return RUN_TETHERED;
      }
    } 
    if(strcmp((char *)this->data,".Start.") == 0)
    {
       this->run_mode = RUN_STANDALONE;
       return RUN_STANDALONE;
    } 
  }
  if (cnt == -1)
    syslog(LOG_WARNING, "[%s]: read error: %s", __FUNCTION__, strerror(errno));
  close(this->fd_uart);
  if(this->run_mode == RUN_COMMANDLINE)
     return RUN_COMMANDLINE;
  this->run_mode = RUN_NOTEST;
  return RUN_NOTEST;
}

/*--------------------------------------------------------------------------*\
 * exported functions
\*--------------------------------------------------------------------------*/
int main(int argc, char **argv)
{
  struct midi9_mainloop_t *loop;
  struct testhw_runtime *this;
  //int run_command_line = input_params(argc, argv);
  /* debug logging. */
  openlog("testhw", LOG_PERROR | LOG_CONS | LOG_NDELAY, LOG_LOCAL1);
  setlogmask(LOG_UPTO(LOG_ERR));
  signal(SIGTERM, term);
  signal(SIGABRT, term);

  /* allocate global data */
  if ((this = calloc(1, sizeof(struct testhw_runtime))) == NULL)
  {
    syslog(LOG_CRIT, "not enough memory: %s", strerror(errno));
    exit(0);
  }  
  this->run_mode = input_params(argc, argv);
  if ((this->data = calloc(MAX_BUF_SIZE, sizeof(unsigned char))) == NULL)
  {
    free(this);
    syslog(LOG_CRIT, "not enough memory: %s", strerror(errno));
    exit(0);
  }  
  if ((this->midi_data = calloc(MAX_BUF_SIZE, sizeof(unsigned char))) == NULL)
  {
    free(this);
    syslog(LOG_CRIT, "not enough memory: %s", strerror(errno));
    exit(0);
  }  
  if (midi9_ipc_shared_mem_connect((void **)&this->sharedmem, sizeof(struct midi9d_sharedmem), SHAREDMEM_MIDI9D) != 0)
    syslog(LOG_ERR, "[%s]: Sharedmem failure", __FUNCTION__);

  if(test_uart_open(this, MIDI9_SERIAL_PORT_TESTHW, (MIDI_BAUD_RATE*4)))
  {
    loop = midi9_mainloop_new(this);
    /* uart */
    this->loop = loop;
    this->fd_uart          = midi9_mainloop_uart_poll_add(loop, MIDI9_SERIAL_PORT_TESTHW, (MIDI_BAUD_RATE*4), uart_handler);
    this->fd_midiconn_uart = midi9_mainloop_uart_poll_add(this->loop, MIDI9_SERIAL_PORT_MIDI, MIDI_BAUD_RATE,       uart_midi_handler);
    if ((this->fd_buttons = midi9_mainloop_device_poll_add(loop, MIDI9_DEVICE_BUTTONS, button_device_handler)) < 0)
      syslog(LOG_ERR, "[%s] Buttons driver open failed %s", argv[0], strerror(errno));
    
    this->fd_test_log      = fopen(TESTHW_LOG_FILE, "a");//"/usr/local/share/midi9/testhw.log"
    
    system("kill $(pidof midiconn)"); 
    /* timer */
    if(this->run_mode == RUN_TETHERED)
      this->test_state             = TEST_IDLE;
    else if(this->run_mode == RUN_STANDALONE)
      this->test_state             = STST_IDLE;
    else if(this->run_mode == RUN_COMMANDLINE)
      this->test_state             = STST_IDLE;
    
    this->button_bools           = 0;
    this->tests_passed           = 0;
    this->tests_failed           = 0;
    this->time_to_wait           = 0;
    this->time_wait_started      = 0;
    this->midi_in_count          = 0;
    this->tester_on              = 0;
    this->power_good             = IGNORED;
    this->tester_serial_loop_on  = 0;
    this->tester_pedal_loop_on   = 0;
    this->tester_pedal_drive_on  = 0;
    this->test_rail_current_on   = 0;
    this->test_pedal_current_on  = 0;
    gettimeofday(&this->lasttime, NULL);
    gettimeofday(&this->thistime, NULL);
    gettimeofday(&this->flashtime, NULL);
    midi9_mainloop_timeout_add(loop, TIMER_INVERVAL_MS, timer_handler, this);
    
    g_loop = loop;
    midi9_mainloop_run(loop);
    /* clean up */
    fclose(this->fd_test_log);
  }
  else 
      syslog(LOG_NOTICE,"[%s]No handshake found",__FUNCTION__); 

  /* clean up */
  midi9_ipc_shared_mem_release(this->sharedmem);
  free(this->data);
  free(this);
  closelog();
  signal(SIGABRT, SIG_DFL);
  signal(SIGTERM, SIG_DFL);
  exit(EXIT_SUCCESS);
}
