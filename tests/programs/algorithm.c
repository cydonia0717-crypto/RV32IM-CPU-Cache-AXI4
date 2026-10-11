// Freestanding integration workload: loops, calls, data cache and integer M.
volatile unsigned *const output=(unsigned *)0xfff0;
volatile int a[64];
__attribute__((noinline)) int gcd(int x,int y) { while(y) { int t=x%y; x=y; y=t; } return x; }
int main(void) {
 for(int i=0;i<64;i++) a[i]=(i*73+19)%101;
 for(int i=1;i<64;i++) {
  int v=a[i],j=i;
  while(j>0 && a[j-1]>v) { a[j]=a[j-1]; --j; }
  a[j]=v;
 }
 unsigned sum=0;
 for(int i=0;i<64;i++) sum+=a[i];
 unsigned g=gcd(12345,315);
 *output=(sum==3247 && g==15) ? 1 : 2;
 return 0;
}
