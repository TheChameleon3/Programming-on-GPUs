#include "stdio.h"
#include "stdlib.h"
#include <sys/time.h>
#include "math.h"

/*

CPU - @size=1500 & nIter = 1 : 7.6358 seconds  @size=1500 & nIter = 10 : 77.839
GPU - @size=1500 & nIter = 1 : 0.34319 seconds @size=1500 & nIter = 10 : 2.0269

after first running the program with just the kernel pragmas in place it
was clear that the program was running very nicely and the profiler
showed that there was one set of copyin's and one of copy outs per iterations
it was clear that adding a data pragma would be of no help as the program
the data could not be brought in and out any more efficiently.

having seen this i tested it and proved that it did in fact make no difference
this can be seen in the commented out code. The next step taken was to find out why?
After investigating it shows that the gpu implicitaly does the same copyin's and out's
as i had done explicitally.




*/


int main (int argc, char **argv);

void fillMatrix(int size, float **restrict A) {
   for (int i = 0; i < size; ++i) {
      for (int j = 0; j < size; ++j) {
        A[i][j] = ((float)i);
      }
   }
}
float** MatrixMult(int size, float **restrict A, float **restrict B, float **restrict C) {
  //#pragma acc data copyin(B[:size][:size],A[:size][:size]) copyout(C[:size][:size])
  {
  #pragma acc kernels
   for (int i = 0; i < size; ++i) {
     for (int j = 0; j < size; ++j) {
       float tmp = 0.;
       for (int k = 0; k < size; ++k) {
          tmp += A[i][k] * B[k][j];
       }
       C[i][j] = tmp;
     }
   }
 }
   return C;

}
float** MakeMatrix(int size, float **restrict arr) {
    int i;
    arr = (float **)malloc( sizeof(float *) * size);
    arr[0] = (float *)malloc( sizeof(float) * size * size);
    for (i=1; i<size; i++){
       arr[i] = (float *)(arr[i-1] + size);
    }
    return arr;
}
void showMatrix(int size, float **restrict arr) {
   int i, j;
   for (i=0; i<size; i++){
      for (j=0; j<size; j++){
         printf("arr[%d][%d]=%f \n",i,j,arr[i][j]);
      }
   }
}
void copyMatrix(float **restrict A, float **restrict B, int size){
//#pragma acc data copyout(A[:size][:size]) copyin(B[:size][:size])
{
  #pragma acc kernels
   for (int i=0; i<size; ++i){
      for (int j=0; j<size; ++j){
         A[i][j] = B[i][j];
      }
   }
}
}
int main (int argc, char **argv) {
   int i, j, k;
   float **A, **B, **C;

  // if (argc != 3) {
  //    fprintf(stderr,"Use: %s size nIter\n", argv[0]);
//      return -1;
//   }
   int size = 1500;
   int nIter = 10;

   if (nIter <= 0) {
      fprintf(stderr,"%s: Invalid nIter (%d)\n", argv[0],nIter);
      return -1;
   }

    struct timeval start_time, stop_time;  // timers

    A = (float**)MakeMatrix(size, A);
   fillMatrix(size, A);
   B = (float**)MakeMatrix(size, B);
   fillMatrix(size, B);
   C = (float**)MakeMatrix(size, C);

   gettimeofday(&start_time,NULL); // Unix timer

   for (int i=0; i<nIter; i++) {
      C = MatrixMult(size, A, B, C);
      if (i%2==1) {
         copyMatrix(A, C, size); //multiply A by B and assign back to A on even iterations
      }
      else {
         copyMatrix(B, C, size); //multiply A by B and assign back to B on odd iterations
      }
   }
   gettimeofday(&stop_time,NULL);
   float diff = ( (stop_time.tv_sec-start_time.tv_sec)*1000000 + (stop_time.tv_usec - start_time.tv_usec) )/1000000.0;

   printf("%s total runtime %8.5g\n", argv[0], diff);
   free(A); free(B); free(C);
   return 0;
}
