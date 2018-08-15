
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <stdio.h>
#include <helper_cuda.h>

/*
 * This example implements matrix element-wise addition on the host and GPU.
 * sumMatrixOnHost iterates over the rows and columns of each matrix, adding
 * elements from A and B together and storing the results in C. The current
 * offset in each matrix is stored using pointer arithmetic. sumMatrixOnGPU2D
 * implements the same logic, but using CUDA threads to process each matrix.
 */

void initialData(float *ip, const int size)
{
    int i;

    for(i = 0; i < size; i++)
    {
        ip[i] = (float)( rand() & 0xFF ) / 10.0f;
    }
}

void sumMatrixOnHost(float *A, float *B, float *C, const int nx, const int ny)
{
    float *ia = A;
    float *ib = B;
    float *ic = C;

    for (int iy = 0; iy < ny; iy++)
    {
        for (int ix = 0; ix < nx; ix++)
        {
            ic[ix] = ia[ix] + ib[ix];
        }

        ia += nx;
        ib += nx;
        ic += nx;
    }

    return;
}

void checkResult(float *hostRef, float *gpuRef, const int N)
{
    double epsilon = 1.0E-8;

    for (int i = 0; i < N; i++)
    {
        if (abs(hostRef[i] - gpuRef[i]) > epsilon)
        {
            printf("host %f gpu %f ", hostRef[i], gpuRef[i]);
            printf("Arrays do not match.\n\n");
            break;
        }
    }
}

// grid 2D block 2D
__global__ void sumMatrixOnGPU2D(float *A, float *B, float *C, int NX, int NY)
{
    unsigned int ix = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned int iy = blockIdx.y * blockDim.y + threadIdx.y;
    unsigned int idx = iy * NX + ix;

    if (ix < NX && iy < NY)
    {
        C[idx] = A[idx] + B[idx];
    }
}

// grid 1D block 2D
__global__ void sumMatrixOnGPU1D(float *A, float *B, float *C, int NXY)
{
    unsigned int idx = blockIdx.x * blockDim.x * blockDim.y + threadIdx.y * blockDim.x + threadIdx.x;

    if (idx < NXY)
    {
        C[idx] = A[idx] + B[idx];
    }
}

// grid 1d block 2d 16 data per thread

__global__ void sumMatrixOnGPU1D16data(float *A, float *B, float *C, int NXY)
{
    unsigned int idx = blockIdx.x * blockDim.x * blockDim.y + threadIdx.y * blockDim.x + threadIdx.x;//iy * NX + ix;
    int i =0;
    if(idx < NXY)
    {
        while (i < 16 )//&& iy < NY)
        {
            C[idx] = A[idx] + B[idx];
            i++;
        }
        i=0;
    }
}


int main(int argc, char **argv)
{
    // set up device
    int dev = 0;
    cudaDeviceProp deviceProp;
    checkCudaErrors(cudaGetDeviceProperties(&deviceProp, dev));
    checkCudaErrors(cudaSetDevice(dev));

    // set up data size of matrix
    int nx = 1 << 12;  // 14
    int ny = 1 << 12;

    int nxy = nx * ny;
    int nBytes = nxy * sizeof(float);

    // malloc host memory
    float *h_A, *h_B, *hostRef, *gpuRef;
    h_A = (float *)malloc(nBytes);
    h_B = (float *)malloc(nBytes);
    hostRef = (float *)malloc(nBytes);
    gpuRef = (float *)malloc(nBytes);

    initialData(h_A, nxy);
    initialData(h_B, nxy);

    memset(hostRef, 0, nBytes);
    memset(gpuRef, 0, nBytes);

    // add matrix at host side for result checks
    sumMatrixOnHost (h_A, h_B, hostRef, nx, ny);

	// malloc device global memory
    float *d_MatA, *d_MatB, *d_MatC;
    checkCudaErrors(cudaMalloc((void **)&d_MatA, nBytes));
    checkCudaErrors(cudaMalloc((void **)&d_MatB, nBytes));
    checkCudaErrors(cudaMalloc((void **)&d_MatC, nBytes));

   // setup kernel launch parameters
    int dimx = 64; // default block size if no runtime parameters given
    int dimy = 2;

    if(argc > 2)
    {
        dimx = atoi(argv[1]);
        dimy = atoi(argv[2]);
    }

	dim3 block(dimx, dimy);
   	dim3 grid2d((nx + block.x - 1) / block.x, (ny + block.y - 1) / block.y);
	dim3 grid1d(((nx + block.x - 1) / block.x)* (ny + block.y - 1) / block.y);

    // transfer data from host to device
    checkCudaErrors(cudaMemcpy(d_MatA, h_A, nBytes, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(d_MatB, h_B, nBytes, cudaMemcpyHostToDevice));

	// initialise CUDA timing
	float milli2d,milli1d,milli1d16;
	cudaEvent_t start2d, stop2d,start1d, stop1d,start1d16, stop1d16;
	cudaEventCreate(&start2d);
	cudaEventCreate(&stop2d);
	cudaEventRecord(start2d);
  cudaEventCreate(&start1d);
	cudaEventCreate(&stop1d);
	cudaEventRecord(start1d);
  cudaEventCreate(&start1d16);
	cudaEventCreate(&stop1d16);
	cudaEventRecord(start1d16);// start timing

	// execute the kernel
    checkCudaErrors(cudaDeviceSynchronize());
    sumMatrixOnGPU2D<<<grid2d, block>>>(d_MatA, d_MatB, d_MatC, nx, ny);
    cudaEventRecord(stop2d);
    sumMatrixOnGPU1D<<<grid1d, block>>>(d_MatA, d_MatB, d_MatC, nxy);
    cudaEventRecord(stop1d);
    sumMatrixOnGPU1D16data<<<grid1d, block>>>(d_MatA, d_MatB, d_MatC, nxy);
    cudaEventRecord(stop1d16);
	  checkCudaErrors(cudaEventSynchronize(stop2d));
	  cudaEventElapsedTime(&milli2d, start2d, stop2d);
    checkCudaErrors(cudaEventSynchronize(stop1d));
	  cudaEventElapsedTime(&milli1d, start1d, stop1d);
    checkCudaErrors(cudaEventSynchronize(stop1d16));
	  cudaEventElapsedTime(&milli1d16, start1d16, stop1d16);// time random generation

	printf("sumMatrixOnGPU2D <<<(%d,%d), (%d,%d)>>> (ms): %f \n", grid2d.x, grid2d.y,
           block.x, block.y, milli2d);
	printf("sumMatrixOnGPU1D <<<(%d,%d), (%d,%d)>>> (ms): %f \n", grid1d.x, grid1d.y,
           block.x, block.y, milli1d);
	printf("sumMatrixOnGPU1D16data <<<(%d,%d), (%d,%d)>>> (ms): %f \n", grid1d.x, grid1d.y,
           block.x, block.y, milli1d16);

    checkCudaErrors(cudaGetLastError());

    // copy kernel result back to host side
    checkCudaErrors(cudaMemcpy(gpuRef, d_MatC, nBytes, cudaMemcpyDeviceToHost));

    // checkCudaErrors device results
    checkResult(hostRef, gpuRef, nxy);

    // free device global memory
    checkCudaErrors(cudaFree(d_MatA));
    checkCudaErrors(cudaFree(d_MatB));
    checkCudaErrors(cudaFree(d_MatC));

    // free host memory
    free(h_A);
    free(h_B);
    free(hostRef);
    free(gpuRef);

    // reset device
    checkCudaErrors(cudaDeviceReset());

    return EXIT_SUCCESS;
}
