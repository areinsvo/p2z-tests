/*
icc propagate-toz-test.C -o propagate-toz-test.exe -fopenmp -O3
*/
#include <cuda_profiler_api.h>
#include "cuda_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <unistd.h>
#include <sys/time.h>
#include <vector>
#include <Eigen/Dense>
#include <Eigen/Core>

#ifndef bsize
#define bsize 1
#endif
#ifndef ntrks
#define ntrks 9600
#endif

#define nb    ntrks/bsize
#ifndef nevts
#define nevts 100
#endif
#define smear 0.1

#ifndef NITER
#define NITER 100
#endif
#ifndef num_streams
#define num_streams 1
#endif

#ifndef threadsperblockx
#define threadsperblockx 32
#endif
#define threadsperblocky 1024/threadsperblockx
#ifndef blockspergrid
#define blockspergrid 10
#endif

#define HOSTDEV __host__ __device__

using namespace Eigen;
//using Eigen::VectorXt;
//typedef Matrix<size_t, Dynamic, Dynamic> MatrixXt;
//typedef Matrix<size_t, Dynamic, 1> VectorXt;
//typedef Matrix<float, Dynamic, 1> VectorXf;


HOSTDEV size_t PosInMtrx(size_t i, size_t j, size_t D) {
  return i*D+j;
}

HOSTDEV size_t SymOffsets33(size_t i) {
  VectorXd offs(9);
  offs << 0, 1, 3, 1, 2, 4, 3, 4, 5;
  return offs(i);
}

HOSTDEV size_t SymOffsets66(size_t i) {
  VectorXf offs(36);
  offs << 0, 1, 3, 6, 10, 15, 1, 2, 4, 7, 11, 16, 3, 4, 5, 8, 12, 17, 6, 7, 8, 9, 13, 18, 10, 11, 12, 13, 14, 19, 15, 16, 17, 18, 19, 20;
  return offs(i);
}

struct ATRK {
  //float par[6];
  //float cov[21];
  Matrix<float,6,1> par;
  Matrix<float,21,1> cov;
  int q;
  //int hitidx[22];
  Matrix<float,22,1> hitidx;
};

struct AHIT {
  Matrix<float,3,1> pos;
  Matrix<float,6,1> cov;
};

struct MP1I {
  Matrix<int,1,1> data[bsize];
  //VectorXi data(1*bsize);
};
struct MP22I {
  Matrix<int,22,1> data[bsize];
  //VectorXi data(22*bsize);
};

struct MP3F {
  //Matrix<float,3,1> data[bsize];
  Vector3f data[bsize];
};

struct MP6F {
  Matrix<float,6,1> data[bsize];
  //VectorXf data(6*bsize);
};

struct MP3x3SF {
  //float data[6*bsize];
  //Matrix<float,3,3> data[bsize];
  Matrix3f data[bsize];
};

struct MP6x6SF {
  Matrix<float,6,6> data[bsize];
};

struct MP6x6F {
  Matrix<float,6,6> data[bsize];
  //MatrixXf data(6*bsize,6*bsize);
};

struct MPTRK {
  MP6F    par;
  MP6x6SF cov;
  MP1I    q;
  MP22I   hitidx;
};                                                                                                                   
//struct ALLTRKS {
//  MPTRK  btrks[nevts*ntrks];
//};

struct MPHIT {
  MP3F    pos;
  MP3x3SF cov;
};



float randn(float mu, float sigma) {
  float U1, U2, W, mult;
  static float X1, X2;
  static int call = 0;
  if (call == 1) {
    call = !call;
    return (mu + sigma * (float) X2);
  } do {
    U1 = -1 + ((float) rand () / RAND_MAX) * 2;
    U2 = -1 + ((float) rand () / RAND_MAX) * 2;
    W = pow (U1, 2) + pow (U2, 2);
  }
  while (W >= 1 || W == 0);
  mult = sqrt ((-2 * log (W)) / W);
  X1 = U1 * mult;
  X2 = U2 * mult;
  call = !call;
  return (mu + sigma * (float) X1);
}

MPTRK* prepareTracks(ATRK inputtrk) {
  MPTRK* result = (MPTRK*) malloc(nevts*nb*sizeof(MPTRK));
  //MPTRK* result;
  //cudaMallocManaged((void**)&result,nevts*nb*sizeof(MPTRK)); //fixme, align?
  //cudaMemAdvise(result,nevts*nb*sizeof(MPTRK),cudaMemAdviseSetPreferredLocation,cudaCpuDeviceId);
  for (size_t ie=0;ie<nevts;++ie) {
    for (size_t ib=0;ib<nb;++ib) {
      for (size_t it=0;it<bsize;++it) {
        //par
        for (size_t ip=0;ip<6;++ip) {
          result[ib + nb*ie].par.data[it](ip) = (1+smear*randn(0,1))*inputtrk.par[ip];
        }
        //cov
        for (size_t ip=0;ip<21;++ip) {
          result[ib + nb*ie].cov.data[it](ip) = (1+smear*randn(0,1))*inputtrk.cov[ip];
        }
        //q
        result[ib + nb*ie].q.data[it](0) = inputtrk.q-2*ceil(-0.5 + (float)rand() / RAND_MAX);//fixme check
      }
    }
  }
  return result;
}

MPHIT* prepareHits(AHIT inputhit) {
  MPHIT* result = (MPHIT*) malloc(nevts*nb*sizeof(MPHIT));
  //MPHIT* result;
  //cudaMallocManaged((void**)&result,nevts*nb*sizeof(MPHIT));  //fixme, align?
  //cudaMemAdvise(result,nevts*nb*sizeof(MPHIT),cudaMemAdviseSetPreferredLocation,cudaCpuDeviceId);
  for (size_t ie=0;ie<nevts;++ie) {
    for (size_t ib=0;ib<nb;++ib) {
      for (size_t it=0;it<bsize;++it) {
        //pos
        for (size_t ip=0;ip<3;++ip) {
          result[ib + nb*ie].pos.data[it](ip) = (1+smear*randn(0,1))*inputhit.pos[ip];
        }
        //cov
        for (size_t ip=0;ip<6;++ip) {
          result[ib + nb*ie].cov.data[it](ip) = (1+smear*randn(0,1))*inputhit.cov[ip];
        }
      }
    }
  }
  return result;
}


HOSTDEV MPTRK* bTk(MPTRK* tracks, size_t ev, size_t ib) {
  return &(tracks[ib + nb*ev]);
}

HOSTDEV const MPTRK* bTk(const MPTRK* tracks, size_t ev, size_t ib) {
  return &(tracks[ib + nb*ev]);
}


HOSTDEV float q(const MP1I* bq, size_t it){
  return (*bq).data[it](0);
}

HOSTDEV float par(const MP6F* bpars, size_t it, size_t ipar){
  return (*bpars).data[it](ipar);
}
HOSTDEV float x    (const MP6F* bpars, size_t it){ return par(bpars, it, 0); }
HOSTDEV float y    (const MP6F* bpars, size_t it){ return par(bpars, it, 1); }
HOSTDEV float z    (const MP6F* bpars, size_t it){ return par(bpars, it, 2); }
HOSTDEV float ipt  (const MP6F* bpars, size_t it){ return par(bpars, it, 3); }
HOSTDEV float phi  (const MP6F* bpars, size_t it){ return par(bpars, it, 4); }
HOSTDEV float theta(const MP6F* bpars, size_t it){ return par(bpars, it, 5); }

HOSTDEV float par(const MPTRK* btracks, size_t it, size_t ipar){
  return par(&(*btracks).par,it,ipar);
}
HOSTDEV float x    (const MPTRK* btracks, size_t it){ return par(btracks, it, 0); }
HOSTDEV float y    (const MPTRK* btracks, size_t it){ return par(btracks, it, 1); }
HOSTDEV float z    (const MPTRK* btracks, size_t it){ return par(btracks, it, 2); }
HOSTDEV float ipt  (const MPTRK* btracks, size_t it){ return par(btracks, it, 3); }
HOSTDEV float phi  (const MPTRK* btracks, size_t it){ return par(btracks, it, 4); }
HOSTDEV float theta(const MPTRK* btracks, size_t it){ return par(btracks, it, 5); }

HOSTDEV float par(const MPTRK* tracks, size_t ev, size_t tk, size_t ipar){
  size_t ib = tk/bsize;
  const MPTRK* btracks = bTk(tracks, ev, ib);
  size_t it = tk % bsize;
  return par(btracks, it, ipar);
}

HOSTDEV float x    (const MPTRK* tracks, size_t ev, size_t tk){ return par(tracks, ev, tk, 0); }
HOSTDEV float y    (const MPTRK* tracks, size_t ev, size_t tk){ return par(tracks, ev, tk, 1); }
HOSTDEV float z    (const MPTRK* tracks, size_t ev, size_t tk){ return par(tracks, ev, tk, 2); }
HOSTDEV float ipt  (const MPTRK* tracks, size_t ev, size_t tk){ return par(tracks, ev, tk, 3); }
HOSTDEV float phi  (const MPTRK* tracks, size_t ev, size_t tk){ return par(tracks, ev, tk, 4); }
HOSTDEV float theta(const MPTRK* tracks, size_t ev, size_t tk){ return par(tracks, ev, tk, 5); }

HOSTDEV void setpar(MP6F* bpars, size_t it, size_t ipar, float val){
  (*bpars).data[it](ipar) = val;
}
HOSTDEV void setx    (MP6F* bpars, size_t it, float val){ return setpar(bpars, it, 0, val); }
HOSTDEV void sety    (MP6F* bpars, size_t it, float val){ return setpar(bpars, it, 1, val); }
HOSTDEV void setz    (MP6F* bpars, size_t it, float val){ return setpar(bpars, it, 2, val); }
HOSTDEV void setipt  (MP6F* bpars, size_t it, float val){ return setpar(bpars, it, 3, val); }
HOSTDEV void setphi  (MP6F* bpars, size_t it, float val){ return setpar(bpars, it, 4, val); }
HOSTDEV void settheta(MP6F* bpars, size_t it, float val){ return setpar(bpars, it, 5, val); }

HOSTDEV void setpar(MPTRK* btracks, size_t it, size_t ipar, float val){
  return setpar(&(*btracks).par,it,ipar,val);
}
HOSTDEV void setx    (MPTRK* btracks, size_t it, float val){ return setpar(btracks, it, 0, val); }
HOSTDEV void sety    (MPTRK* btracks, size_t it, float val){ return setpar(btracks, it, 1, val); }
HOSTDEV void setz    (MPTRK* btracks, size_t it, float val){ return setpar(btracks, it, 2, val); }
HOSTDEV void setipt  (MPTRK* btracks, size_t it, float val){ return setpar(btracks, it, 3, val); }
HOSTDEV void setphi  (MPTRK* btracks, size_t it, float val){ return setpar(btracks, it, 4, val); }
HOSTDEV void settheta(MPTRK* btracks, size_t it, float val){ return setpar(btracks, it, 5, val); }

HOSTDEV MPHIT* bHit(MPHIT* hits, size_t ev, size_t ib) {
  return &(hits[ib + nb*ev]);
}
HOSTDEV const MPHIT* bHit(const MPHIT* hits, size_t ev, size_t ib) {
  return &(hits[ib + nb*ev]);
}

HOSTDEV float pos(const MP3F* hpos, size_t it, size_t ipar){
  return (*hpos).data[it](ipar);
}
HOSTDEV float x(const MP3F* hpos, size_t it)    { return pos(hpos, it, 0); }
HOSTDEV float y(const MP3F* hpos, size_t it)    { return pos(hpos, it, 1); }
HOSTDEV float z(const MP3F* hpos, size_t it)    { return pos(hpos, it, 2); }

HOSTDEV float pos(const MPHIT* hits, size_t it, size_t ipar){
  return pos(&(*hits).pos,it,ipar);
}
HOSTDEV float x(const MPHIT* hits, size_t it)    { return pos(hits, it, 0); }
HOSTDEV float y(const MPHIT* hits, size_t it)    { return pos(hits, it, 1); }
HOSTDEV float z(const MPHIT* hits, size_t it)    { return pos(hits, it, 2); }

HOSTDEV float pos(const MPHIT* hits, size_t ev, size_t tk, size_t ipar){
  size_t ib = tk/bsize;
  const MPHIT* bhits = bHit(hits, ev, ib);
  size_t it = tk % bsize;
  return pos(bhits,it,ipar);
}
HOSTDEV float x(const MPHIT* hits, size_t ev, size_t tk)    { return pos(hits, ev, tk, 0); }
HOSTDEV float y(const MPHIT* hits, size_t ev, size_t tk)    { return pos(hits, ev, tk, 1); }
HOSTDEV float z(const MPHIT* hits, size_t ev, size_t tk)    { return pos(hits, ev, tk, 2); }



#define N bsize
//HOSTDEV void MultHelixPropEndcap(const MP6x6F* A, const MP6x6SF* B, MP6x6F* C) {
__forceinline__ __device__ void MultHelixPropEndcap(const MP6x6F* A, const MP6x6SF* B, MP6x6F* C) {
  const Matrix<float,6,6> *a = (*A).data; //ASSUME_ALIGNED(a, 64);
  const Matrix<float,6,6> *b = (*B).data; //ASSUME_ALIGNED(b, 64);
  Matrix<float,6,6> *c = (*C).data;       //ASSUME_ALIGNED(c, 64);
  //printf("a test %f\n", A->data(1,1));
  for(size_t it=threadIdx.x;it<bsize;it+=blockDim.x){
    c[it].noalias() = a[it]*b[it];
  }
}

//HOSTDEV void MultHelixPropTranspEndcap(MP6x6F* A, MP6x6F* B, MP6x6SF* C) {
__forceinline__ __device__ void MultHelixPropTranspEndcap(MP6x6F* A, MP6x6F* B, MP6x6SF* C) {
  const Matrix<float,6,6> *a = (*A).data; //ASSUME_ALIGNED(a, 64);
  const Matrix<float,6,6> *b = (*B).data; //ASSUME_ALIGNED(b, 64);
  Matrix<float,6,6> *c = (*C).data;       //ASSUME_ALIGNED(c, 64);
  for(size_t it=threadIdx.x;it<bsize;it+=blockDim.x){
    c[it].noalias()= a[it]*b[it].transpose();
  }
}

//HOSTDEV void propagateToZ(const MP6x6SF* inErr, const MP6F* inPar,
__device__ __forceinline__ void propagateToZ(const MP6x6SF* inErr, const MP6F* inPar,
			  const MP1I* inChg,const MP3F* msP, 
			  MP6x6SF* outErr, MP6F* outPar
			){//struct MP6x6F* errorProp, struct MP6x6F* temp) {
  //printf("testx\n");
  MP6x6F errorProp, temp;
  for(size_t it=threadIdx.x;it<bsize;it+=blockDim.x){
    const float zout = z(msP,it);
    //printf("testx %f\n",zout);
    const float k = q(inChg,it)*100/3.8;
    const float deltaZ = zout - z(inPar,it);
    const float pt = 1./ipt(inPar,it);
    const float cosP = cosf(phi(inPar,it));
    const float sinP = sinf(phi(inPar,it));
    const float cosT = cosf(theta(inPar,it));
    const float sinT = sinf(theta(inPar,it));
    const float pxin = cosP*pt;
    const float pyin = sinP*pt;
    const float alpha = deltaZ*sinT*ipt(inPar,it)/(cosT*k);
    const float sina = sinf(alpha); // this can be approximated;
    const float cosa = cosf(alpha); // this can be approximated;
    outPar->data[it](0,0) = x(inPar,it) + k*(pxin*sina - pyin*(1.-cosa));
    outPar->data[it](1,0) = y(inPar,it) + k*(pyin*sina + pxin*(1.-cosa));
    outPar->data[it](2,0) = zout;
    outPar->data[it](3,0) = ipt(inPar,it);
    outPar->data[it](4,0) = phi(inPar,it)+alpha;
    outPar->data[it](5,0) = theta(inPar,it);
    
    const float sCosPsina = sinf(cosP*sina);
    const float cCosPsina = cosf(cosP*sina);
    
    for (size_t i=0;i<6;++i) errorProp.data[it](i,i) = 1.;
    errorProp.data[it](0,2) = cosP*sinT*(sinP*cosa*sCosPsina-cosa)/cosT;
    errorProp.data[it](0,3) = cosP*sinT*deltaZ*cosa*(1.-sinP*sCosPsina)/(cosT*ipt(inPar,it))-k*(cosP*sina-sinP*(1.-cCosPsina))/(ipt(inPar,it)*ipt(inPar,it));
    errorProp.data[it](0,4) = (k/ipt(inPar,it))*(-sinP*sina+sinP*sinP*sina*sCosPsina-cosP*(1.-cCosPsina));
    errorProp.data[it](0,5) = cosP*deltaZ*cosa*(1.-sinP*sCosPsina)/(cosT*cosT);
    errorProp.data[it](1,2) = cosa*sinT*(cosP*cosP*sCosPsina-sinP)/cosT;
    errorProp.data[it](1,3) = sinT*deltaZ*cosa*(cosP*cosP*sCosPsina+sinP)/(cosT*ipt(inPar,it))-k*(sinP*sina+cosP*(1.-cCosPsina))/(ipt(inPar,it)*ipt(inPar,it));
    errorProp.data[it](1,4) = (k/ipt(inPar,it))*(-sinP*(1.-cCosPsina)-sinP*cosP*sina*sCosPsina+cosP*sina);
    errorProp.data[it](1,5) = deltaZ*cosa*(cosP*cosP*sCosPsina+sinP)/(cosT*cosT);
    errorProp.data[it](4,2) = -ipt(inPar,it)*sinT/(cosT*k);
    errorProp.data[it](4,3) = sinT*deltaZ/(cosT*k);
    errorProp.data[it](4,5) = ipt(inPar,it)*deltaZ/(cosT*cosT*k);
  }
  __syncthreads();
  MultHelixPropEndcap(&errorProp, inErr, &temp);
  __syncthreads();
  MultHelixPropTranspEndcap(&errorProp, &temp, outErr);
}



__global__ void GPUsequence(MPTRK* trk, MPHIT* hit, MPTRK* outtrk, const int stream){
  //printf("test 1\n");
  for (size_t ie = blockIdx.x; ie<nevts/num_streams; ie+=gridDim.x){
  //printf("test 2\n");
    for(size_t ib = threadIdx.y; ib <nb; ib+=blockDim.y){
      const MPTRK* btracks = bTk(trk,ie+stream*nevts/num_streams,ib);
      const MPHIT* bhits = bHit(hit,ie+stream*nevts/num_streams,ib);
      //printf("show: %f\n", (bhits->pos).data[0](0));
      MPTRK* obtracks = bTk(outtrk,ie+stream*nevts/num_streams,ib);
   //   ///*__shared__*/ struct MP6x6F errorProp, temp;
 // printf("test 3\n");
	
      propagateToZ(&(*btracks).cov, &(*btracks).par, &(*btracks).q, &(*bhits).pos, 
                   &(*obtracks).cov, &(*obtracks).par);
                   //&(*obtracks).cov, &(*obtracks).par, &errorProp, &temp);
    }
  }
}


void transfer(MPTRK* trk, MPHIT* hit, MPTRK* trk_dev, MPHIT* hit_dev){

   
  cudaMemcpy(trk_dev, trk, nevts*nb*sizeof(MPTRK), cudaMemcpyHostToDevice);
  cudaMemcpy(&trk_dev->par, &trk->par, sizeof(MP6F), cudaMemcpyHostToDevice);
  cudaMemcpy(&((trk_dev->par).data), &((trk->par).data), bsize*sizeof(Matrix<float,6,1>), cudaMemcpyHostToDevice);
  //cudaMemcpy(&((trk_dev->par).data), &((trk->par).data), bsize*sizeof(Matrix<float,6,1>), cudaMemcpyHostToDevice);
  cudaMemcpy(&trk_dev->cov, &trk->cov, sizeof(MP6x6SF), cudaMemcpyHostToDevice);
  cudaMemcpy(&((trk_dev->cov).data), &((trk->cov).data), bsize*sizeof(Matrix<float,6,6>), cudaMemcpyHostToDevice);
  cudaMemcpy(&trk_dev->q, &trk->q, sizeof(MP1I), cudaMemcpyHostToDevice);
  cudaMemcpy(&((trk_dev->q).data), &((trk->q).data), bsize*sizeof(Matrix<int,1,1>), cudaMemcpyHostToDevice);
  cudaMemcpy(&trk_dev->hitidx, &trk->hitidx, sizeof(MP22I), cudaMemcpyHostToDevice);
  cudaMemcpy(&((trk_dev->hitidx).data), &((trk->hitidx).data), bsize*sizeof(Matrix<int,22,1>), cudaMemcpyHostToDevice);
  //for(int i =0; i<bsize;i++){
  ////printf("host: %f %d %d\n",trk->par.data[i](0),sizeof(trk->par.data), sizeof(Matrix<float,6,1>));
  //cudaMemcpy(&((trk_dev->par).data[i]), &((trk->par).data[i]), sizeof(Matrix<float,6,1>), cudaMemcpyHostToDevice);
  ////printf("dev: %f\n",trk_dev->par.data[i](0));
  //}
    

  printf("host: %f\n",trk->par.data[0](0));
  printf("dev: %f\n",trk_dev->par.data[0](0));
  cudaMemcpy(hit_dev,hit,nevts*nb*sizeof(MPHIT), cudaMemcpyHostToDevice);
  cudaMemcpy(&hit_dev->pos,&hit->pos,sizeof(MP3F), cudaMemcpyHostToDevice);
  cudaMemcpy(&(hit_dev->pos).data,&(hit->pos).data,bsize*sizeof(Matrix<float,3,1>), cudaMemcpyHostToDevice);
  cudaMemcpy(&hit_dev->cov,&hit->cov,sizeof(MP3x3SF), cudaMemcpyHostToDevice);
  cudaMemcpy(&(hit_dev->cov).data,&(hit->cov).data,bsize*sizeof(Matrix<float,3,3>), cudaMemcpyHostToDevice);
}
void transfer_back(MPTRK* trk, MPTRK* trk_host){
  cudaMemcpy(trk_host, trk, nevts*nb*sizeof(MPTRK), cudaMemcpyDeviceToHost);
  cudaMemcpy(&trk_host->par, &trk->par, sizeof(MP6F), cudaMemcpyDeviceToHost);
  cudaMemcpy(&((trk_host->par).data), &((trk->par).data), bsize*sizeof(Matrix<float,6,1>), cudaMemcpyDeviceToHost);
  cudaMemcpy(&trk_host->cov, &trk->cov, sizeof(MP6x6SF), cudaMemcpyDeviceToHost);
  cudaMemcpy(&((trk_host->cov).data), &((trk->cov).data), bsize*sizeof(Matrix<float,6,6>), cudaMemcpyDeviceToHost);
  cudaMemcpy(&trk_host->q, &trk->q, sizeof(MP1I), cudaMemcpyDeviceToHost);
  cudaMemcpy(&((trk_host->q).data), &((trk->q).data), bsize*sizeof(Matrix<int,1,1>), cudaMemcpyDeviceToHost);
  cudaMemcpy(&trk_host->hitidx, &trk->hitidx, sizeof(MP22I), cudaMemcpyDeviceToHost);
  cudaMemcpy(&((trk_host->hitidx).data), &((trk->hitidx).data), bsize*sizeof(Matrix<int,22,1>), cudaMemcpyDeviceToHost);
}

/////////////////////test functions/////////////////////////////////
//__global__ void printtest(Matrix3d *a, Matrix3d *b, Matrix3d *c){
//        int n =1;
//        int idx = blockIdx.x * blockDim.x + threadIdx.x;
//        if(idx < n)
//        {
//            c[idx] = a[idx] * b[idx];
//            printf("printtest \n");
//            printf("printtest %f\n",c[idx](0));
//        }
//        return;
//}
//    __global__ void cu_dot(Vector3d *v1, Vector3d *v2, double *out)
//    {
//        int n = 1;
//        int idx = blockIdx.x * blockDim.x + threadIdx.x;
//        if(idx < n)
//        {
//            out[idx] = v1[idx].dot(v2[idx]);
//            printf("dottest \n");
//            printf("dottest %f\n",out[idx]);
//        }
//        return;
//    }
//////////////////////////////////////////////////////////////////



int main (int argc, char* argv[]) {

  printf("RUNNING CUDA!!\n");
  ATRK inputtrk = {
     {-12.806846618652344, -7.723824977874756, 38.13014221191406,0.23732035065189902, -2.613372802734375, 0.35594117641448975},
     {6.290299552347278e-07,4.1375109560704004e-08,7.526661534029699e-07,2.0973730840978533e-07,1.5431574240665213e-07,9.626245400795597e-08,-2.804026640189443e-06,
      6.219111130687595e-06,2.649119409845118e-07,0.00253512163402557,-2.419662877381737e-07,4.3124190760040646e-07,3.1068903991780678e-09,0.000923913115050627,
      0.00040678296006807003,-7.755406890332818e-07,1.68539375883925e-06,6.676875566525437e-08,0.0008420574605423793,7.356584799406111e-05,0.0002306247719158348},
     1,
     {1, 0, 17, 16, 36, 35, 33, 34, 59, 58, 70, 85, 101, 102, 116, 117, 132, 133, 152, 169, 187, 202}
  };

  AHIT inputhit = {
     {-20.7824649810791, -12.24150276184082, 57.8067626953125},
     {2.545517190810642e-06,-2.6680759219743777e-06,2.8030024168401724e-06,0.00014160551654640585,0.00012282167153898627,11.385087966918945}
  };
  printf("track in pos: %f, %f, %f \n", inputtrk.par[0], inputtrk.par[1], inputtrk.par[2]);
  printf("track in cov: %.2e, %.2e, %.2e \n", inputtrk.cov[SymOffsets66(PosInMtrx(0,0,6))],
                                              inputtrk.cov[SymOffsets66(PosInMtrx(1,1,6))],
                                              inputtrk.cov[SymOffsets66(PosInMtrx(2,2,6))]);
  printf("hit in pos: %f %f %f \n", inputhit.pos[0], inputhit.pos[1], inputhit.pos[2]);

  printf("produce nevts=%i ntrks=%i smearing by=%f \n", nevts, ntrks, smear);
  printf("NITER=%d\n", NITER);
 
  long start_wall, end_wall, start_setup, end_setup; 
  struct timeval timecheck;
  cudaEvent_t start, end, copy,copyback;
  cudaEventCreate(&start);
  cudaEventCreate(&copy);
  cudaEventCreate(&copyback);
  cudaEventCreate(&end);
      
  gettimeofday(&timecheck, NULL);
  start_setup = (long)timecheck.tv_sec * 1000 + (long)timecheck.tv_usec / 1000;
  MPTRK* trk = prepareTracks(inputtrk);
  MPHIT* hit = prepareHits(inputhit);
  MPTRK* trk_dev;
  MPHIT* hit_dev;
  MPTRK* outtrk = (MPTRK*) malloc(nevts*nb*sizeof(MPTRK));
  MPTRK* outtrk_dev;
  cudaMalloc((MPTRK**)&trk_dev,nevts*nb*sizeof(MPTRK));  
  cudaMalloc((MPTRK**)&hit_dev,nevts*nb*sizeof(MPHIT));
  cudaMalloc((MPTRK**)&outtrk_dev,nevts*nb*sizeof(MPTRK));  
  //cudaMallocManaged((void**)&outtrk,nevts*nb*sizeof(MPTRK));
  dim3 grid(blockspergrid,1,1);
  dim3 block(threadsperblockx,threadsperblocky,1); 
  int device = -1;
  cudaGetDevice(&device);
  int stream_chunk = ((int)(nevts/num_streams))*nb;//*sizeof(MPTRK);
  int stream_remainder = ((int)(nevts%num_streams))*nb;//*sizeof(MPTRK);
  int stream_range;
  if (stream_remainder == 0){ stream_range =num_streams;}
  else{stream_range = num_streams+1;}
  cudaStream_t streams[stream_range];
  for (int s = 0; s<stream_range;s++){
    cudaStreamCreateWithFlags(&streams[s],cudaStreamNonBlocking);
  }
  gettimeofday(&timecheck, NULL);
  end_setup = (long)timecheck.tv_sec * 1000 + (long)timecheck.tv_usec / 1000;
 

  printf("done preparing!\n");
  //long start, end;
  //long start2, end2;
  //struct timeval timecheck;

  printf("Size of struct MPTRK trk[] = %ld\n", nevts*nb*sizeof(struct MPTRK));
  printf("Size of struct MPTRK outtrk[] = %ld\n", nevts*nb*sizeof(struct MPTRK));
  printf("Size of struct struct MPHIT hit[] = %ld\n", nevts*nb*sizeof(struct MPHIT));

///////////////////////////////////////TEST Functions///////////////////////////////////////////// 
//std::vector<Matrix3d> m1(10, Matrix3d{{ 1.0, 1.0, 1.0},{1.0,1.0,1.0},{1.0,1.0,1.0 }});
//std::vector<Matrix3d> m2(10, Matrix3d{{ -1.0, 1.0, 1.0},{1.0,1.0,1.0},{1.0,1.0,1.0 }});
//  Matrix3d* A_dev;// =Matrix<float,6*bsize,6*bsize>::Random(6*bsize,6*bsize);
//  Matrix3d* B_dev;// =Matrix<float,6*bsize,6*bsize>::Random(6*bsize,6*bsize);
//  Matrix3d* C_dev;// =Matrix<float,6*bsize,6*bsize>::Random(6*bsize,6*bsize);
//  int n = 1;
//  cudaMalloc((void**)&A_dev,sizeof(Matrix3d)*n);
//  cudaMalloc((void**)&B_dev,sizeof(Matrix3d)*n);
//  cudaMalloc((void**)&C_dev,sizeof(Matrix3d)*n);
//
//  cudaMemcpy(A_dev, m1.data(), sizeof(Matrix3d)*n, cudaMemcpyHostToDevice);
//  cudaMemcpy(B_dev, m2.data(), sizeof(Matrix3d)*n, cudaMemcpyHostToDevice);
//
//printtest<<<1,1>>>(A_dev,B_dev,C_dev);
//
//
//std::vector<Vector3d> v1(10, Vector3d{ 1.0, 1.0, 1.0 });
//std::vector<Vector3d> v2(10, Vector3d{ -1.0, 1.0, 1.0 });
//Vector3d *dev_v1, *dev_v2;
//        cudaMalloc((void **)&dev_v1, sizeof(Vector3d)*n);
//        cudaMalloc((void **)&dev_v2, sizeof(Vector3d)*n);
//        double* dev_ret;
//        cudaMalloc((void **)&dev_ret, sizeof(double)*n);
//
//        // Copy to device
//        cudaMemcpy(dev_v1, v1.data(), sizeof(Vector3d)*n, cudaMemcpyHostToDevice);
//        cudaMemcpy(dev_v2, v2.data(), sizeof(Vector3d)*n, cudaMemcpyHostToDevice);
//
//        // Dot product
//        cu_dot<<<1,1>>>(dev_v1, dev_v2, dev_ret);
/////////////////////////////////////////

  cudaEventRecord(start);	
  gettimeofday(&timecheck, NULL);
  start_wall = (long)timecheck.tv_sec * 1000 + (long)timecheck.tv_usec / 1000;
  transfer(trk,hit,trk_dev,hit_dev);
//  for (int s = 0; s<num_streams;s++){
//    cudaMemPrefetchAsync(trk,nevts*nb*sizeof(MPTRK), device,streams[s]);
//    cudaMemPrefetchAsync(hit,nevts*nb*sizeof(MPHIT), device,streams[s]);
//  }
//  cudaMemAdvise(trk,nevts*nb*sizeof(MPTRK),cudaMemAdviseSetPreferredLocation,device);
//  cudaMemAdvise(hit,nevts*nb*sizeof(MPHIT),cudaMemAdviseSetPreferredLocation,device);
//  cudaMemAdvise(trk,nevts*nb*sizeof(MPTRK),cudaMemAdviseSetReadMostly,device);
//  cudaMemAdvise(hit,nevts*nb*sizeof(MPHIT),cudaMemAdviseSetReadMostly,device);


  cudaEventRecord(copy);	
  cudaEventSynchronize(copy);
  for(int itr=0; itr<NITER; itr++){
    for (int s = 0; s<num_streams;s++){
      //printf("testx\n");
  	  GPUsequence<<<grid,block,0,streams[s]>>>(trk_dev,hit_dev,outtrk_dev,s);
  	  //GPUsequence<<<grid,block,0,streams[s]>>>(trk_dev+(s*stream_chunk),hit_dev+(s*stream_chunk),outtrk_dev+(s*stream_chunk),s);
  	  //GPUsequence<<<grid,block,0,streams[s]>>>(trk,hit,outtrk,s);
    }  
    //if(stream_remainder != 0){
    //  GPUsequence<<<grid,block,0,streams[num_streams]>>>(trk_dev+(num_streams*stream_chunk),hit_dev+(num_streams*stream_chunk),outtrk_dev+(num_streams*stream_chunk),num_streams);
    //}
	  //cudaDeviceSynchronize(); // Normal sync

  } //end itr loop
  cudaDeviceSynchronize(); // shaves a few seconds
  
  cudaEventRecord(copyback);
  cudaEventSynchronize(copyback);
  transfer_back(outtrk_dev,outtrk);
  //for (int s = 0; s<num_streams;s++){
  //  cudaMemPrefetchAsync(outtrk,nevts*nb*sizeof(MPTRK), cudaCpuDeviceId,streams[s]);
  //}
  cudaDeviceSynchronize(); // shaves a few seconds
  gettimeofday(&timecheck, NULL);
  end_wall = (long)timecheck.tv_sec * 1000 + (long)timecheck.tv_usec / 1000;
  cudaEventRecord(end);
  cudaEventSynchronize(end);
  float elapsedtime,copytime,copybacktime,regiontime = 0;
  cudaEventElapsedTime(&regiontime,start,end);
  cudaEventElapsedTime(&elapsedtime,copy,copyback);
  cudaEventElapsedTime(&copytime,start,copy);
  cudaEventElapsedTime(&copybacktime,copyback,end);
  
  for (int s = 0; s<stream_range;s++){
    cudaStreamDestroy(streams[s]);
  }
 

   long walltime = end_wall-start_wall; 
   printf("done ntracks=%i tot time=%f (s) time/trk=%e (s)\n", nevts*ntrks*int(NITER), (elapsedtime)*0.001, (elapsedtime)*0.001/(nevts*ntrks));
   printf("data region time=%f (s)\n", regiontime*0.001);
   printf("memory transfer time=%f (s)\n", (copytime+copybacktime)*0.001);
   printf("setup time time=%f (s)\n", (end_setup-start_setup)*0.001);
   printf("formatted %i %i %i %i %i %f %f %f %f %i\n",int(NITER), nevts,ntrks, bsize, nb, (elapsedtime)*0.001, (regiontime)*0.001,  (copytime+copybacktime)*0.001, (end_setup-start_setup)*0.001, num_streams);

   printf("wall region time=%f (s)\n", (end_wall-start_wall)*0.001);
   float avgx = 0, avgy = 0, avgz = 0;
   float avgdx = 0, avgdy = 0, avgdz = 0;
   for (size_t ie=0;ie<nevts;++ie) {
     for (size_t it=0;it<ntrks;++it) {
       float x_ = x(outtrk,ie,it);
       float y_ = y(outtrk,ie,it);
       float z_ = z(outtrk,ie,it);
       avgx += x_;
       avgy += y_;
       avgz += z_;
       float hx_ = x(hit,ie,it);
       float hy_ = y(hit,ie,it);
       float hz_ = z(hit,ie,it);
       avgdx += (x_-hx_)/x_;
       avgdy += (y_-hy_)/y_;
       avgdz += (z_-hz_)/z_;
     }
   }
   avgx = avgx/float(nevts*ntrks);
   avgy = avgy/float(nevts*ntrks);
   avgz = avgz/float(nevts*ntrks);
   avgdx = avgdx/float(nevts*ntrks);
   avgdy = avgdy/float(nevts*ntrks);
   avgdz = avgdz/float(nevts*ntrks);

   float stdx = 0, stdy = 0, stdz = 0;
   float stddx = 0, stddy = 0, stddz = 0;
   for (size_t ie=0;ie<nevts;++ie) {
     for (size_t it=0;it<ntrks;++it) {
       float x_ = x(outtrk,ie,it);
       float y_ = y(outtrk,ie,it);
       float z_ = z(outtrk,ie,it);
       stdx += (x_-avgx)*(x_-avgx);
       stdy += (y_-avgy)*(y_-avgy);
       stdz += (z_-avgz)*(z_-avgz);
       float hx_ = x(hit,ie,it);
       float hy_ = y(hit,ie,it);
       float hz_ = z(hit,ie,it);
       stddx += ((x_-hx_)/x_-avgdx)*((x_-hx_)/x_-avgdx);
       stddy += ((y_-hy_)/y_-avgdy)*((y_-hy_)/y_-avgdy);
       stddz += ((z_-hz_)/z_-avgdz)*((z_-hz_)/z_-avgdz);
     }
   }

   stdx = sqrtf(stdx/float(nevts*ntrks));
   stdy = sqrtf(stdy/float(nevts*ntrks));
   stdz = sqrtf(stdz/float(nevts*ntrks));
   stddx = sqrtf(stddx/float(nevts*ntrks));
   stddy = sqrtf(stddy/float(nevts*ntrks));
   stddz = sqrtf(stddz/float(nevts*ntrks));

   printf("track x avg=%f std/avg=%f\n", avgx, fabs(stdx/avgx));
   printf("track y avg=%f std/avg=%f\n", avgy, fabs(stdy/avgy));
   printf("track z avg=%f std/avg=%f\n", avgz, fabs(stdz/avgz));
   printf("track dx/x avg=%f std=%f\n", avgdx, stddx);
   printf("track dy/y avg=%f std=%f\n", avgdy, stddy);
   printf("track dz/z avg=%f std=%f\n", avgdz, stddz);
	
   cudaFree(trk);
   cudaFree(hit);
   cudaFree(outtrk);
   
return 0;
}

