#include <RcppEigen.h>
#include <RcppParallel.h>

// [[Rcpp::depends(RcppEigen)]]

using namespace RcppParallel;
using Eigen::Map;               	// 'maps' rather than copies
using Eigen::MatrixXd;                  // variable size matrix, double precision
using Eigen::VectorXd;                  // variable size vector, double precision
// using Eigen::SelfAdjointEigenSolver;    // one of the eigenvalue solvers
using Eigen::Upper;
using Eigen::Lower;
typedef Eigen::MappedSparseMatrix<double> MSpMat;
typedef Eigen::SparseMatrix<double> SpMat;


// [[Rcpp::export]]
MatrixXd chol_solve_mat1(MSpMat R, Map<MatrixXd> B) {
  MatrixXd x;
  R *= 10;
  x = R.triangularView<Upper>().solve(B);
  return x;
}

// [[Rcpp::export]]
MatrixXd chol_solve_mat2(MSpMat R, Map<MatrixXd> B) {
  int n = R.rows();
  int b = B.cols();
  MatrixXd x(n,b);
  for(int i = 0; i < b; i++){
    x.col(i) = R.triangularView<Upper>().solve(B.col(i));
  }
  return x;
}
