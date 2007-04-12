#include <stdio.h>
#include <stdlib.h>  /* atoi,exit */
#include <unistd.h>  /* getopt */
#include <string.h>  /* memset */

#include "../gptl.h"

#ifdef HAVE_PAPI
#include <papi.h>
#endif

double add (int, double);
double multiply (int, int, double);
double multadd (int, double);
double divide (int, double);
double compare (int, int);

int main (int argc, char **argv)
{
  int nompiter = 128;
  int looplen = 1000000;
  int iter;
  int papiopt;
  int c;

  double ret;

  extern char *optarg;

  printf ("Purpose: test known-length loops with various floating point ops\n");
  printf ("Include PAPI and OpenMP, respectively, if enabled\n");
  printf ("Usage: %s [-l looplen] [-n nompiter] [-p papi_option_name]\n", argv[0]);

  while ((c = getopt (argc, argv, "l:n:p:")) != -1) {
    switch (c) {
	case 'l':
	  looplen = atoi (optarg);
	  printf ("Set looplen=%d\n", looplen);
	  break;
	case 'n':
	  nompiter = atoi (optarg);
	  printf ("Set nompiter=%d\n", nompiter);
	  break;
	case 'p':
	  if ((papiopt = GPTL_PAPIname2id (optarg)) >= 0) {
	    printf ("Failure from GPTL_PAPIname2id\n");
	    exit (1);
	  }
	  if (GPTLsetoption (papiopt, 1) < 0) {
	    printf ("Failure from GPTLsetoption (%s,1)\n", optarg);
	    exit (1);
	  }
	  break;
	default:
	  printf ("unknown option %c\n", c);
	  exit (2);
    }
  }
  
  printf ("Outer loop length (OMP)=%d\n", nompiter);
  printf ("Inner loop length=%d\n", looplen);

  (void) GPTLsetoption (GPTLabort_on_error, 1);
  (void) GPTLsetoption (GPTLoverhead, 0);
  (void) GPTLsetoption (GPTLnarrowprint, 1);

  GPTLinitialize ();
  GPTLstart ("total");
	 
#pragma omp parallel for private (iter, ret)
      
  for (iter = 1; iter <= nompiter; iter++) {
    ret = add (looplen, 0.);
    ret = multiply (looplen, iter, 0.);
    ret = multadd (looplen, 0.);
    ret = divide (looplen, 1.);
    ret = compare (looplen, iter);
  }

  GPTLstop ("total");
  GPTLpr (0);
  if (GPTLfinalize () < 0)
    exit (6);

  return 0;
}

double add (int looplen, double zero)
{
  int i;
  char string[128];
  double val = zero;

  if (looplen < 1000000)
    sprintf (string, "%dadditions", looplen);
  else
    sprintf (string, "%-.3gadditions", (double) looplen);

  if (GPTLstart (string) < 0)
    exit (1);

  for (i = 1; i <= looplen; ++i)
      val += zero;

  if (GPTLstop (string) < 0)
    exit (1);

  return val;
}

double multiply (int looplen, int iter, double zero)
{
  int i;
  char string[128];
  double val = iter;

  if (looplen < 1000000)
    sprintf (string, "%dmultiplies", looplen);
  else
    sprintf (string, "%-.3gmultiplies", (double) looplen);

  if (GPTLstart (string) < 0)
    exit (1);

  for (i = 1; i <= looplen; ++i) {
    val *= zero;
  }

  if (GPTLstop (string) < 0)
    exit (1);

  return val;
}

double multadd (int looplen, double zero)
{
  int i;
  char string[128];
  double val = zero;

  if (looplen < 1000000)
    sprintf (string, "%dmultadds", looplen);
  else
    sprintf (string, "%-.3gmultadds", (double) looplen);

  if (GPTLstart (string) < 0)
    exit (1);

  for (i = 1; i <= looplen; ++i)
    val += zero * i;

  if (GPTLstop (string) < 0)
    exit (1);

  return val;
}

double divide (int looplen, double one)
{
  int i;
  char string[128];
  double val = one;

  if (looplen < 1000000)
    sprintf (string, "%ddivides", looplen);
  else
    sprintf (string, "%-.3gdivides", (double) looplen);

  if (GPTLstart (string) < 0)
    exit (1);

  for (i = 1; i <= looplen; ++i)
    val /= one;

  if (GPTLstop (string) < 0)
    exit (1);

  return val;
}

double compare (int looplen, int iter)
{
  int i;
  char string[128];
  double val = iter;

  if (looplen < 1000000)
    sprintf (string, "%ddivides", looplen);
  else
    sprintf (string, "%-.3gcompares", (double) looplen);

  if (GPTLstart (string) < 0)
    exit (1);

  for (i = 0; i < looplen; ++i)
    if (val < i)
      val = i;

  if (GPTLstop (string) < 0)
    exit (1);

  return val;
}
